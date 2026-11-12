<?php

namespace App\Http\Controllers\Api\Erp\Sales;

use App\Http\Controllers\Controller;
use App\Models\Erp\Customer;
use App\Models\Erp\Sales\PriceList;
use App\Services\AuditLogger;
use App\Services\Erp\Sales\SalesPricing;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * Price lists, their dated product prices, and which customers follow each.
 * A customer follows a list through customers.price_list, which holds its code.
 */
class PriceListController extends Controller
{
    public function __construct(private readonly TenantContext $tenant, private readonly AuditLogger $audit, private readonly SalesPricing $pricing) {}

    public function index(): JsonResponse
    {
        $lists = PriceList::query()->withCount('items')->orderByDesc('is_default')->orderBy('name')->get();
        $followers = Customer::query()->whereNotNull('price_list')->selectRaw('price_list, COUNT(*) as n')->groupBy('price_list')->pluck('n', 'price_list');

        return response()->json(['data' => $lists->map(fn ($l) => [...$l->toArray(), 'customers_count' => (int) ($followers[$l->code] ?? 0)])]);
    }

    public function show(PriceList $priceList): JsonResponse
    {
        return response()->json(['data' => [
            ...$priceList->load(['items' => fn ($q) => $q->orderBy('product_id')->orderBy('effective_from'), 'items.product:id,sku,name,sale_price,unit_id', 'items.product.unit:id,code'])->toArray(),
            'customers' => Customer::query()->where('price_list', $priceList->code)->orderBy('name')->get(['id', 'code', 'name', 'city']),
        ]]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->rules($request);
        $list = DB::transaction(function () use ($data, $request) {
            if ($data['is_default'] ?? false) {
                PriceList::query()->update(['is_default' => false]);
            }

            return PriceList::create([...$data, 'created_by' => $request->user()->id]);
        });
        $this->audit->log('sales.price_list.created', "Created price list {$list->name}", $list);

        return response()->json(['data' => $list], 201);
    }

    public function update(Request $request, PriceList $priceList): JsonResponse
    {
        $data = $this->rules($request, $priceList->id);
        DB::transaction(function () use ($data, $priceList) {
            if (($data['is_default'] ?? false) && ! $priceList->is_default) {
                PriceList::query()->update(['is_default' => false]);
            }

            if ($data['code'] !== $priceList->code) {
                // Customers follow the list by code: carry them across.
                Customer::query()->where('price_list', $priceList->code)->update(['price_list' => $data['code']]);
            }

            $priceList->update($data);
        });
        $this->audit->log('sales.price_list.updated', "Updated price list {$priceList->name}", $priceList);

        return response()->json(['data' => $priceList]);
    }

    /**
     * Replaces the list's prices. Each row is a product, a price and the date
     * it takes effect; a later row for the same product supersedes it from
     * its own date, so price history stays readable.
     */
    public function items(Request $request, PriceList $priceList): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'items' => ['present', 'array', 'max:2000'],
            'items.*.product_id' => ['required', 'integer', Rule::exists('products', 'id')->where('company_id', $company)],
            'items.*.unit_price' => ['required', 'numeric', 'min:0', 'max:9999999999'],
            'items.*.effective_from' => ['required', 'date'],
            'items.*.effective_to' => ['nullable', 'date', 'after_or_equal:items.*.effective_from'],
        ]);

        $seen = [];
        foreach ($data['items'] as $item) {
            $key = $item['product_id'].'@'.substr($item['effective_from'], 0, 10);
            if (isset($seen[$key])) {
                throw new RuntimeException('A product can have only one price starting on the same date.');
            }
            $seen[$key] = true;
        }

        DB::transaction(function () use ($priceList, $data) {
            $priceList->items()->delete();
            foreach ($data['items'] as $item) {
                $priceList->items()->create($item);
            }
        });
        $this->audit->log('sales.price_list.prices', 'Set '.count($data['items'])." prices on {$priceList->name}", $priceList);

        return $this->show($priceList->fresh());
    }

    /** Points customers at this list (or, with detach, back to the default). */
    public function customers(Request $request, PriceList $priceList): JsonResponse
    {
        $data = $request->validate([
            'customer_ids' => ['present', 'array'],
            'customer_ids.*' => ['integer', Rule::exists('customers', 'id')->where('company_id', $this->tenant->id())],
        ]);

        DB::transaction(function () use ($priceList, $data) {
            Customer::query()->where('price_list', $priceList->code)->whereNotIn('id', $data['customer_ids'] ?: [0])->update(['price_list' => null]);
            Customer::query()->whereIn('id', $data['customer_ids'] ?: [0])->update(['price_list' => $priceList->code]);
        });
        $this->audit->log('sales.price_list.customers', 'Assigned '.count($data['customer_ids'])." customers to {$priceList->name}", $priceList);

        return $this->show($priceList);
    }

    public function destroy(PriceList $priceList): JsonResponse
    {
        if (Customer::query()->where('price_list', $priceList->code)->exists()) {
            throw new RuntimeException("Customers still buy from {$priceList->name}. Move them to another list or deactivate it instead.");
        }

        $priceList->delete();
        $this->audit->log('sales.price_list.deleted', "Deleted price list {$priceList->name}", $priceList);

        return response()->json(['message' => 'Price list deleted.']);
    }

    /** What a customer pays for each product on a date. */
    public function prices(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'customer_id' => ['nullable', 'integer', Rule::exists('customers', 'id')->where('company_id', $company)],
            'date' => ['nullable', 'date'],
            'product_ids' => ['nullable', 'array'],
            'product_ids.*' => ['integer'],
        ]);
        $customer = isset($data['customer_id']) ? Customer::query()->find($data['customer_id']) : null;
        $ids = $data['product_ids'] ?? DB::table('products')->where('company_id', $company)->where('is_active', true)->pluck('id')->all();

        return response()->json([
            'data' => $this->pricing->prices($customer, array_map('intval', $ids), $data['date'] ?? null),
            'price_list' => $this->pricing->listFor($customer)?->only(['id', 'code', 'name']),
            'tax_rate' => $this->pricing->defaultTaxRate(),
        ]);
    }

    private function rules(Request $request, ?int $ignore = null): array
    {
        return $request->validate([
            'code' => ['required', 'string', 'max:40', 'alpha_dash', Rule::unique('price_lists', 'code')->where('company_id', $this->tenant->id())->ignore($ignore)],
            'name' => ['required', 'string', 'max:120'],
            'is_default' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
            'notes' => ['nullable', 'string', 'max:255'],
        ]);
    }
}
