<?php

namespace App\Services\Erp\Production;

use App\Models\Erp\Production\ProductionOrder;
use App\Models\Erp\Production\ProductionReceipt;
use App\Models\Erp\StockDocument;
use App\Models\Erp\StockMovement;
use Illuminate\Support\Carbon;

/**
 * Read-only views over production: the overview figures and batch genealogy.
 * Everything here is derived from the orders, receipts and the stock ledger,
 * never stored twice.
 */
class ProductionInsights
{
    /** @return array<string, mixed> */
    public function overview(int $days = 30): array
    {
        $since = now()->subDays($days - 1)->startOfDay();
        $today = now()->toDateString();

        $byStatus = ProductionOrder::query()->selectRaw('status, count(*) as n')->groupBy('status')->pluck('n', 'status')
            ->map(fn ($n) => (int) $n)->all();

        $period = ProductionReceipt::query()->where('receipt_date', '>=', $since->toDateString());
        $produced = (float) (clone $period)->sum('produced_quantity');
        $released = (float) (clone $period)->sum('released_quantity');
        $wastage = (float) (clone $period)->sum('wastage_quantity');
        $rejected = (float) (clone $period)->sum('rejected_quantity')
            + (float) (clone $period)->where('status', ProductionReceipt::STATUS_REJECTED)->sum('good_quantity');

        $todayRows = ProductionReceipt::query()->where('receipt_date', $today);

        $daily = ProductionReceipt::query()
            ->where('receipt_date', '>=', now()->subDays(13)->toDateString())
            ->selectRaw('receipt_date as day, SUM(produced_quantity) as produced, SUM(released_quantity) as released, SUM(wastage_quantity) as wastage')
            ->groupBy('receipt_date')
            ->get()
            ->keyBy(fn ($r) => Carbon::parse($r->day)->toDateString());

        $trend = collect(range(13, 0))->map(function ($ago) use ($daily) {
            $day = now()->subDays($ago)->toDateString();
            $row = $daily[$day] ?? null;

            return [
                'date' => $day,
                'produced' => (float) ($row->produced ?? 0),
                'released' => (float) ($row->released ?? 0),
                'wastage' => (float) ($row->wastage ?? 0),
            ];
        })->values()->all();

        $issuedValue = -1 * (float) StockMovement::query()
            ->whereHas('document', fn ($q) => $q->where('source_type', ProductionOrder::SOURCE)->where('type', StockDocument::TYPE_ISSUE))
            ->where('movement_date', '>=', $since->toDateString())
            ->sum('value');

        $byProduct = ProductionReceipt::query()
            ->where('receipt_date', '>=', $since->toDateString())
            ->join('production_orders', 'production_orders.id', '=', 'production_receipts.production_order_id')
            ->join('products', 'products.id', '=', 'production_orders.product_id')
            ->groupBy('products.id', 'products.name', 'products.sku')
            ->selectRaw('products.id, products.name, products.sku, SUM(production_receipts.produced_quantity) as produced, SUM(production_receipts.released_quantity) as released, SUM(production_receipts.wastage_quantity) as wastage')
            ->orderByDesc('released')
            ->get()
            ->map(fn ($r) => [
                'product_id' => (int) $r->id, 'name' => $r->name, 'sku' => $r->sku,
                'produced' => (float) $r->produced, 'released' => (float) $r->released, 'wastage' => (float) $r->wastage,
                'yield_percent' => (float) $r->produced > 0 ? round((float) $r->released / (float) $r->produced * 100, 1) : null,
            ])->all();

        return [
            'days' => $days,
            'by_status' => array_replace(array_fill_keys(ProductionOrder::STATUSES, 0), $byStatus),
            'open_orders' => ProductionOrder::query()->open()->count(),
            'today' => [
                'produced' => (float) (clone $todayRows)->sum('produced_quantity'),
                'released' => (float) (clone $todayRows)->sum('released_quantity'),
                'receipts' => (clone $todayRows)->count(),
            ],
            'qc_pending' => ProductionReceipt::query()->where('status', ProductionReceipt::STATUS_PENDING)->count(),
            'period' => [
                'produced' => $produced,
                'released' => $released,
                'rejected' => $rejected,
                'wastage' => $wastage,
                'yield_percent' => $produced > 0 ? round($released / $produced * 100, 1) : null,
                'wastage_percent' => $produced > 0 ? round($wastage / $produced * 100, 1) : null,
                'materials_issued_value' => round($issuedValue, 2),
                'variance_closed' => round((float) ProductionOrder::query()->where('closed_at', '>=', $since)->sum('variance_value'), 2),
            ],
            'trend' => $trend,
            'by_product' => $byProduct,
            'recent_orders' => ProductionOrder::query()->with('product:id,sku,name')
                ->whereIn('status', [ProductionOrder::STATUS_RELEASED, ProductionOrder::STATUS_IN_PROGRESS, ProductionOrder::STATUS_PLANNED])
                ->orderBy('planned_start')->limit(6)
                ->get(['id', 'number', 'product_id', 'planned_quantity', 'released_quantity', 'status', 'planned_start', 'planned_end']),
        ];
    }

    /**
     * Traceability for a batch number, both ways: as a finished batch, the
     * material batches its order consumed; as a material batch, the finished
     * batches made from orders it went into.
     *
     * @return array<string, mixed>
     */
    public function genealogy(string $batch, ?int $productId = null): array
    {
        $finished = ProductionReceipt::query()
            ->with(['order:id,number,product_id,status,materials_warehouse_id', 'order.product:id,sku,name', 'qc:id,production_receipt_id,decision,checked_at'])
            ->where('batch_number', $batch)
            ->when($productId, fn ($q, $id) => $q->whereHas('order', fn ($o) => $o->where('product_id', $id)))
            ->get()
            ->map(fn (ProductionReceipt $r) => [
                'receipt' => $this->receiptRow($r),
                'order' => $r->order->only(['id', 'number', 'status']),
                'product' => $r->order->product?->only(['id', 'sku', 'name']),
                'materials' => $this->materialsOf([$r->production_order_id]),
            ])->values()->all();

        $usedIn = StockMovement::query()
            ->with('product:id,sku,name', 'document:id,number,source_id,document_date')
            ->where('batch_number', $batch)
            ->when($productId, fn ($q, $id) => $q->where('product_id', $id))
            ->whereHas('document', fn ($q) => $q->where('source_type', ProductionOrder::SOURCE)
                ->where('type', StockDocument::TYPE_ISSUE)->where('status', StockDocument::STATUS_POSTED))
            ->orderBy('id')
            ->get();

        $orders = ProductionOrder::query()->with('product:id,sku,name', 'receipts')
            ->whereIn('id', $usedIn->pluck('document.source_id')->unique())
            ->get()->keyBy('id');

        $asMaterial = $usedIn->groupBy('document.source_id')->map(function ($movements, $orderId) use ($orders) {
            $order = $orders[$orderId] ?? null;

            return [
                'order' => $order?->only(['id', 'number', 'status']),
                'product' => $order?->product?->only(['id', 'sku', 'name']),
                'material' => $movements->first()->product?->only(['id', 'sku', 'name']),
                'quantity' => round(-1 * (float) $movements->sum('quantity'), 4),
                'documents' => $movements->pluck('document.number')->unique()->values()->all(),
                'finished_batches' => $order ? $order->receipts->map(fn ($r) => $this->receiptRow($r))->values()->all() : [],
            ];
        })->values()->all();

        return ['batch' => $batch, 'as_finished' => $finished, 'as_material' => $asMaterial];
    }

    /** @return list<array<string, mixed>> recent finished batches, to start a search from */
    public function recentBatches(int $limit = 12): array
    {
        return ProductionReceipt::query()
            ->with('order:id,number,product_id', 'order.product:id,sku,name')
            ->whereNotNull('batch_number')
            ->latest('id')->limit($limit)->get()
            ->map(fn ($r) => [...$this->receiptRow($r), 'product' => $r->order?->product?->only(['id', 'sku', 'name']), 'order_number' => $r->order?->number])
            ->all();
    }

    /**
     * @param  list<int>  $orderIds
     * @return list<array<string, mixed>>
     */
    private function materialsOf(array $orderIds): array
    {
        return StockMovement::query()
            ->with('product:id,sku,name')
            ->whereHas('document', fn ($q) => $q->where('source_type', ProductionOrder::SOURCE)->whereIn('source_id', $orderIds)
                ->where('type', StockDocument::TYPE_ISSUE)->where('status', StockDocument::STATUS_POSTED))
            ->get()
            ->groupBy(fn ($m) => $m->product_id.'|'.$m->batch_number)
            ->map(fn ($rows) => [
                'product' => $rows->first()->product?->only(['id', 'sku', 'name']),
                'batch_number' => $rows->first()->batch_number ?: null,
                'quantity' => round(-1 * (float) $rows->sum('quantity'), 4),
                'value' => round(-1 * (float) $rows->sum('value'), 2),
                'references' => $rows->pluck('reference')->unique()->values()->all(),
            ])->values()->all();
    }

    /** @return array<string, mixed> */
    private function receiptRow(ProductionReceipt $receipt): array
    {
        return [
            'id' => $receipt->id,
            'number' => $receipt->number,
            'batch_number' => $receipt->batch_number,
            'expiry_date' => $receipt->expiry_date?->toDateString(),
            'receipt_date' => $receipt->receipt_date?->toDateString(),
            'status' => $receipt->status,
            'good_quantity' => (float) $receipt->good_quantity,
            'released_quantity' => (float) $receipt->released_quantity,
        ];
    }
}
