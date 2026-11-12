<?php

namespace App\Http\Controllers\Api\Erp\Production;

use App\Http\Controllers\Controller;
use App\Models\Erp\Production\Bom;
use App\Services\Erp\Production\Boms;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Bills of materials: versions, components, conversion cost and standard cost. */
class BomController extends Controller
{
    public function __construct(private readonly Boms $boms, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        $page = Bom::query()
            ->with(['product:id,sku,name,unit_id', 'product.unit:id,code', 'workCentre:id,code,name'])
            ->withCount(['lines', 'orders'])
            ->when($request->query('product_id'), fn ($q, $v) => $q->where('product_id', $v))
            ->when($request->query('active') !== null && $request->query('active') !== '', fn ($q) => $q->where('is_active', $request->boolean('active')))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('name', 'like', "%{$v}%")
                ->orWhereHas('product', fn ($p) => $p->where('name', 'like', "%{$v}%")->orWhere('sku', 'like', "%{$v}%"))))
            ->orderBy('product_id')->orderByDesc('version')
            ->paginate(min((int) $request->query('per_page', 30), 100));

        $page->getCollection()->transform(fn (Bom $bom) => [...$bom->toArray(), 'standard_cost' => $this->boms->standardCost($bom)['unit_cost']]);

        return response()->json($page);
    }

    public function show(Bom $bom): JsonResponse
    {
        $bom->load(['lines.product:id,sku,name,type,unit_id,cost_price,track_batches,track_expiry', 'lines.product.unit:id,code,name',
            'product:id,sku,name,unit_id', 'product.unit:id,code,name', 'workCentre', 'creator:id,name'])->loadCount('orders');

        return response()->json(['data' => [
            ...$bom->toArray(),
            'standard' => $this->boms->standardCost($bom),
            'versions' => Bom::query()->where('product_id', $bom->product_id)->orderByDesc('version')
                ->get(['id', 'version', 'name', 'is_active', 'created_at']),
        ]]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->rules($request);

        return response()->json(['data' => $this->boms->create($data, $data['lines'], $request->user())], 201);
    }

    public function update(Request $request, Bom $bom): JsonResponse
    {
        $data = $this->rules($request, false);

        return response()->json(['data' => $this->boms->update($bom, $data, $data['lines'], $request->user())]);
    }

    public function version(Request $request, Bom $bom): JsonResponse
    {
        $copy = $this->boms->newVersion($bom, $request->user());

        return response()->json(['message' => "Version {$copy->version} created.", 'data' => $copy], 201);
    }

    public function activate(Request $request, Bom $bom): JsonResponse
    {
        $bom = $this->boms->activate($bom, $request->user());

        return response()->json(['message' => "Version {$bom->version} is now the one in use.", 'data' => $bom]);
    }

    public function destroy(Request $request, Bom $bom): JsonResponse
    {
        $this->boms->delete($bom, $request->user());

        return response()->json(['message' => 'Bill of materials deleted.']);
    }

    /** @return array<string, mixed> */
    private function rules(Request $request, bool $creating = true): array
    {
        $company = $this->tenant->id();

        return $request->validate([
            'product_id' => [$creating ? 'required' : 'nullable', 'integer', Rule::exists('products', 'id')->where('company_id', $company)],
            'name' => ['nullable', 'string', 'max:160'],
            'output_quantity' => ['required', 'numeric', 'gt:0', 'max:999999999'],
            'work_centre_id' => ['nullable', 'integer', Rule::exists('production_work_centres', 'id')->where('company_id', $company)],
            'labour_cost' => ['nullable', 'numeric', 'min:0', 'max:999999999999'],
            'overhead_cost' => ['nullable', 'numeric', 'min:0', 'max:999999999999'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'lines' => ['required', 'array', 'min:1', 'max:200'],
            'lines.*.product_id' => ['required', 'integer', Rule::exists('products', 'id')->where('company_id', $company)],
            'lines.*.quantity' => ['required', 'numeric', 'gt:0', 'max:999999999'],
            'lines.*.scrap_percent' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'lines.*.note' => ['nullable', 'string', 'max:255'],
        ]);
    }
}
