<?php

namespace App\Http\Controllers\Api\Erp\Production;

use App\Http\Controllers\Controller;
use App\Models\Erp\Production\Bom;
use App\Models\Erp\Production\ProductionOrder;
use App\Services\Erp\Production\Boms;
use App\Services\Erp\Production\ProductionOrders;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Production orders and the actions on them. Each action is its own
 * permission: planning, issuing, recording output and closing are different
 * people's jobs.
 */
class ProductionOrderController extends Controller
{
    public function __construct(
        private readonly ProductionOrders $orders,
        private readonly Boms $boms,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(ProductionOrder::query()
            ->with(['product:id,sku,name,unit_id', 'product.unit:id,code', 'bom:id,version,name', 'outputWarehouse:id,code,name'])
            ->when($request->query('status'), fn ($q, $v) => $v === 'open' ? $q->open() : $q->where('status', $v))
            ->when($request->query('product_id'), fn ($q, $v) => $q->where('product_id', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")
                ->orWhere('reference', 'like', "%{$v}%")
                ->orWhereHas('product', fn ($p) => $p->where('name', 'like', "%{$v}%"))))
            ->latest('planned_start')->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(ProductionOrder $productionOrder): JsonResponse
    {
        $order = $productionOrder->load([
            'product:id,sku,name,unit_id,track_batches,track_expiry', 'product.unit:id,code,name',
            'bom:id,product_id,version,name,output_quantity,labour_cost,overhead_cost,work_centre_id', 'bom.workCentre:id,code,name',
            'materialsWarehouse:id,code,name', 'outputWarehouse:id,code,name',
            'receipts.qc.inspector:id,name', 'receipts.recorder:id,name', 'receipts.stockDocument:id,number,status',
            'creator:id,name', 'releaser:id,name', 'completer:id,name', 'closer:id,name', 'canceller:id,name',
        ]);

        return response()->json(['data' => [
            ...$order->toArray(),
            'requirements' => $this->orders->requirements($order),
            'costing' => $this->orders->costing($order),
            'issues' => $this->orders->issueDocuments($order)->load('lines.product:id,sku,name', 'creator:id,name')
                ->map(fn ($d) => [
                    ...$d->only(['id', 'number', 'document_date', 'status', 'reason', 'posted_at']),
                    'creator' => $d->creator?->only(['id', 'name']),
                    'value' => round(-1 * (float) $d->movements()->sum('value'), 2),
                    'lines' => $d->lines->map(fn ($l) => [
                        'product' => $l->product?->only(['id', 'sku', 'name']),
                        'quantity' => (float) $l->quantity,
                        'batch_number' => $l->batch_number,
                    ])->all(),
                ])->values(),
        ]]);
    }

    /** What an order for this product and quantity would need, before it is created. */
    public function check(Request $request): JsonResponse
    {
        $data = $request->validate([
            'product_id' => ['required', 'integer', Rule::exists('products', 'id')->where('company_id', $this->tenant->id())],
            'bom_id' => ['nullable', 'integer'],
            'planned_quantity' => ['required', 'numeric', 'gt:0'],
            'materials_warehouse_id' => ['required', 'integer', Rule::exists('warehouses', 'id')->where('company_id', $this->tenant->id())],
        ]);

        $bom = isset($data['bom_id'])
            ? Bom::query()->where('product_id', $data['product_id'])->findOrFail($data['bom_id'])
            : Bom::query()->where('product_id', $data['product_id'])->where('is_active', true)->first();

        if (! $bom) {
            return response()->json(['message' => 'This product has no active bill of materials. Create or activate one first.'], 422);
        }

        $draft = new ProductionOrder([
            'planned_quantity' => $data['planned_quantity'],
            'materials_warehouse_id' => $data['materials_warehouse_id'],
        ]);
        $draft->setRelation('bom', $bom->load('lines.product.unit'));

        return response()->json(['data' => [
            'bom' => $bom->only(['id', 'version', 'name', 'output_quantity']),
            'standard' => $this->boms->standardCost($bom),
            'requirements' => $this->orders->requirements($draft),
        ]]);
    }

    public function store(Request $request): JsonResponse
    {
        $order = $this->orders->create($this->rules($request), $request->user());

        return response()->json(['message' => "{$order->number} planned.", 'data' => $order], 201);
    }

    public function update(Request $request, ProductionOrder $productionOrder): JsonResponse
    {
        return response()->json(['data' => $this->orders->update($productionOrder, $this->rules($request), $request->user())]);
    }

    public function release(Request $request, ProductionOrder $productionOrder): JsonResponse
    {
        $order = $this->orders->release($productionOrder, $request->user());

        return response()->json(['message' => "{$order->number} released to production.", 'data' => $order]);
    }

    public function cancel(Request $request, ProductionOrder $productionOrder): JsonResponse
    {
        $reason = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:255']])['reason'];
        $order = $this->orders->cancel($productionOrder, $reason, $request->user());

        return response()->json(['message' => "{$order->number} cancelled.", 'data' => $order]);
    }

    public function issue(Request $request, ProductionOrder $productionOrder): JsonResponse
    {
        $data = $request->validate([
            'document_date' => ['nullable', 'date', 'before_or_equal:today'],
            'note' => ['nullable', 'string', 'max:255'],
            'lines' => ['required', 'array', 'min:1', 'max:100'],
            'lines.*.product_id' => ['required', 'integer'],
            'lines.*.quantity' => ['required', 'numeric', 'gt:0', 'max:999999999'],
            'lines.*.batch_number' => ['nullable', 'string', 'max:60'],
        ]);

        $document = $this->orders->issue($productionOrder, $data['lines'], $request->user(), $data['document_date'] ?? null, $data['note'] ?? null);

        return response()->json(['message' => "Materials issued on {$document->number}.", 'data' => $document], 201);
    }

    public function receive(Request $request, ProductionOrder $productionOrder): JsonResponse
    {
        $data = $request->validate([
            'receipt_date' => ['nullable', 'date', 'before_or_equal:today'],
            'produced_quantity' => ['required', 'numeric', 'gt:0', 'max:999999999'],
            'good_quantity' => ['required', 'numeric', 'min:0', 'max:999999999'],
            'rejected_quantity' => ['nullable', 'numeric', 'min:0', 'max:999999999'],
            'wastage_quantity' => ['nullable', 'numeric', 'min:0', 'max:999999999'],
            'batch_number' => ['nullable', 'string', 'max:60'],
            'expiry_date' => ['nullable', 'date', 'after:today'],
            'is_final' => ['sometimes', 'boolean'],
            'notes' => ['nullable', 'string', 'max:2000'],
        ]);

        $receipt = $this->orders->receive($productionOrder, $data, $request->user());

        return response()->json(['message' => "{$receipt->number} recorded and waiting for its quality check.", 'data' => $receipt], 201);
    }

    public function complete(Request $request, ProductionOrder $productionOrder): JsonResponse
    {
        $order = $this->orders->complete($productionOrder, $request->user());

        return response()->json(['message' => "{$order->number} completed.", 'data' => $order]);
    }

    public function close(Request $request, ProductionOrder $productionOrder): JsonResponse
    {
        $order = $this->orders->close($productionOrder, $request->user());

        return response()->json(['message' => "{$order->number} closed.", 'data' => $order]);
    }

    /** @return array<string, mixed> */
    private function rules(Request $request): array
    {
        $company = $this->tenant->id();
        $warehouse = Rule::exists('warehouses', 'id')->where('company_id', $company)->where('is_active', true);

        return $request->validate([
            'product_id' => ['required', 'integer', Rule::exists('products', 'id')->where('company_id', $company)],
            'bom_id' => ['nullable', 'integer', Rule::exists('production_boms', 'id')->where('company_id', $company)],
            'planned_quantity' => ['required', 'numeric', 'gt:0', 'max:999999999'],
            'materials_warehouse_id' => ['required', 'integer', $warehouse],
            'output_warehouse_id' => ['required', 'integer', $warehouse],
            'planned_start' => ['required', 'date'],
            'planned_end' => ['required', 'date', 'after_or_equal:planned_start'],
            'reference' => ['nullable', 'string', 'max:80'],
            'notes' => ['nullable', 'string', 'max:2000'],
        ]);
    }
}
