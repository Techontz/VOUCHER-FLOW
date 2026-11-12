<?php

namespace App\Http\Controllers\Api\Erp;

use App\Http\Controllers\Controller;
use App\Models\Erp\Product;
use App\Models\Erp\StockBalance;
use App\Models\Erp\StockMovement;
use App\Services\AuditLogger;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class ProductController extends Controller
{
    public function __construct(private readonly TenantContext $tenant, private readonly AuditLogger $audit) {}

    public function index(Request $request): JsonResponse
    {
        $products = Product::query()
            ->with(['category:id,name', 'unit:id,code,name,allows_decimals'])
            ->withSum('balances as on_hand', 'quantity')
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                ->where('name', 'like', "%{$v}%")->orWhere('sku', 'like', "%{$v}%")->orWhere('barcode', $v)))
            ->when($request->query('category_id'), fn ($q, $v) => $q->where('category_id', $v))
            ->when($request->query('type'), fn ($q, $v) => $q->where('type', $v))
            ->when($request->boolean('active_only'), fn ($q) => $q->where('is_active', true))
            ->when($request->boolean('low_stock'), fn ($q) => $q->where('reorder_level', '>', 0)
                ->whereRaw('reorder_level >= (SELECT COALESCE(SUM(b.quantity), 0) FROM stock_balances b WHERE b.product_id = products.id)'))
            ->orderBy('name')
            ->paginate(min((int) $request->query('per_page', 50), 200));

        return response()->json($products);
    }

    public function show(Product $product): JsonResponse
    {
        $product->load(['category:id,name', 'unit']);

        $balances = StockBalance::query()->with('warehouse:id,code,name')
            ->where('product_id', $product->id)->where('quantity', '<>', 0)
            ->orderBy('expiry_date')->get();

        $movements = StockMovement::query()->with('warehouse:id,name', 'creator:id,name')
            ->where('product_id', $product->id)->latest('id')->limit(50)->get();

        return response()->json(['data' => [
            ...$product->toArray(),
            'on_hand' => round((float) $balances->sum('quantity'), 4),
            'stock_value' => round($balances->sum(fn ($b) => (float) $b->quantity * (float) $b->average_cost), 2),
            'balances' => $balances,
            'movements' => $movements,
        ]]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->rules($request);
        $defaults = BusinessConfig::of($this->tenant->company())->setting('product_defaults') ?: [];

        $product = Product::create([...$defaults, ...$data, 'created_by' => $request->user()->id]);
        $this->audit->log('product.created', "Added product {$product->sku} · {$product->name}", $product);

        return response()->json(['data' => $product->load('category:id,name', 'unit')], 201);
    }

    public function update(Request $request, Product $product): JsonResponse
    {
        $data = $this->rules($request, $product);
        $before = $product->only(array_keys($data));
        $product->update($data);
        $this->audit->log('product.updated', "Updated product {$product->sku}", $product, $before, $product->only(array_keys($data)));

        return response()->json(['data' => $product->load('category:id,name', 'unit')]);
    }

    /** A product with history is kept and deactivated: its movements must still resolve. */
    public function destroy(Product $product): JsonResponse
    {
        if (StockMovement::query()->where('product_id', $product->id)->exists()) {
            $product->update(['is_active' => false]);
            $this->audit->log('product.deactivated', "Deactivated product {$product->sku}", $product);

            return response()->json(['message' => "{$product->name} has stock history, so it was deactivated rather than deleted."]);
        }

        $product->delete();
        $this->audit->log('product.deleted', "Deleted product {$product->sku}", $product);

        return response()->json(['message' => "{$product->name} deleted."]);
    }

    private function rules(Request $request, ?Product $product = null): array
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'sku' => [$product ? 'sometimes' : 'required', 'string', 'max:60', Rule::unique('products')->where('company_id', $company)->ignore($product?->id)],
            'barcode' => ['nullable', 'string', 'max:80'],
            'name' => [$product ? 'sometimes' : 'required', 'string', 'max:180'],
            'brand' => ['nullable', 'string', 'max:80'],
            'type' => ['sometimes', Rule::in(Product::TYPES)],
            'category_id' => ['nullable', 'integer', Rule::exists('product_categories', 'id')->where('company_id', $company)],
            'unit_id' => [$product ? 'sometimes' : 'required', 'integer', Rule::exists('units', 'id')->where('company_id', $company)],
            'cost_price' => ['sometimes', 'numeric', 'min:0'],
            'sale_price' => ['sometimes', 'numeric', 'min:0'],
            'reorder_level' => ['sometimes', 'numeric', 'min:0'],
            'track_batches' => ['sometimes', 'boolean'],
            'track_expiry' => ['sometimes', 'boolean'],
            'track_serials' => ['sometimes', 'boolean'],
            'custom_fields' => ['nullable', 'array'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        if (isset($data['custom_fields'])) {
            $data['custom_fields'] = $this->customFields($data['custom_fields']);
        }

        // Tracking cannot be switched off once stock is held against it, or
        // the batches already on the shelf would lose their identity.
        if ($product && $product->balances()->where('quantity', '<>', 0)->exists()) {
            foreach (['track_batches', 'track_expiry', 'track_serials'] as $flag) {
                if (array_key_exists($flag, $data) && (bool) $data[$flag] !== (bool) $product->{$flag}) {
                    throw ValidationException::withMessages([$flag => 'Tracking cannot change while stock is on hand.']);
                }
            }
        }

        return $data;
    }

    /** Keeps only the fields the company defined, each coerced to its declared type. */
    private function customFields(array $values): array
    {
        $defined = collect(BusinessConfig::of($this->tenant->company())->setting('product_fields') ?: [])->keyBy('key');
        $clean = [];

        foreach ($values as $key => $value) {
            $field = $defined[$key] ?? null;

            if (! $field || $value === null || $value === '') {
                continue;
            }

            $clean[$key] = match ($field['type']) {
                'number' => is_numeric($value) ? $value + 0 : throw ValidationException::withMessages(["custom_fields.{$key}" => "{$field['label']} must be a number."]),
                'boolean' => filter_var($value, FILTER_VALIDATE_BOOLEAN),
                'date' => strtotime((string) $value) ? date('Y-m-d', strtotime((string) $value)) : throw ValidationException::withMessages(["custom_fields.{$key}" => "{$field['label']} must be a date."]),
                default => mb_substr((string) $value, 0, 255),
            };
        }

        return $clean;
    }
}
