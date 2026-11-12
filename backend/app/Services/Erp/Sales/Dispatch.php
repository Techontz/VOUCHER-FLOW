<?php

namespace App\Services\Erp\Sales;

use App\Models\Erp\Product;
use App\Models\Erp\Sales\LoadingOrder;
use App\Models\Erp\Sales\LoadingOrderLine;
use App\Models\Erp\Sales\SalesOrder;
use App\Models\Erp\StockBalance;
use App\Models\Erp\StockDocument;
use App\Models\Erp\StockMovement;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use App\Services\Erp\StockDocuments;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Finance verification & dispatch (spec §7), from a released order to the
 * customer's signature:
 *
 *   loading order → loaded quantities → storekeeper confirms (stock leaves,
 *   once) → driver and security confirm → delivery note → gate pass →
 *   proof of delivery → any shortfall decided: back to stock, or written off.
 *
 * Stock leaves at exactly one moment: the storekeeper's confirmation posts a
 * stock issue raised from the loading order (Dr Cost of goods sold, Cr
 * Inventory). The loading order row is locked and its status re-checked
 * first, and the issue document id is kept on it, so it cannot happen twice.
 */
class Dispatch
{
    public function __construct(
        private readonly SalesOrders $orders,
        private readonly StockDocuments $stock,
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    /**
     * @param  array<string, mixed>  $data
     * @param  array<int, float>  $quantities  order line id => quantity to load; empty loads everything outstanding
     */
    public function create(SalesOrder $order, array $data, array $quantities, User $actor): LoadingOrder
    {
        return DB::transaction(function () use ($order, $data, $quantities, $actor) {
            $locked = $this->orders->lock($order);

            if ($locked->status === SalesOrder::STATUS_AWAITING_PAYMENT) {
                $paid = $this->orders->verifiedPayments($locked);
                throw new RuntimeException(sprintf(
                    '%s is waiting for payment verification: TZS %s verified of TZS %s. %s pays before delivery, so finance must verify the payment before a loading order can be created.',
                    $locked->number, number_format($paid, 2), number_format((float) $locked->total, 2), $locked->customer?->name ?? 'This customer',
                ));
            }

            if (! in_array($locked->status, [SalesOrder::STATUS_READY, SalesOrder::STATUS_LOADING, SalesOrder::STATUS_DISPATCHED], true)) {
                throw new RuntimeException("{$locked->number} is ".str_replace('_', ' ', $locked->status).'. Only an approved order released for loading can be loaded.');
            }

            $warehouse = Warehouse::query()->where('is_active', true)->find($data['warehouse_id'] ?? 0)
                ?? throw new RuntimeException('Choose an active warehouse to load from.');
            $remaining = $this->orders->remainingToLoad($locked);
            $orderLines = $locked->lines()->with('product')->get()->keyBy('id');
            $rows = [];

            foreach ($remaining as $lineId => $open) {
                $quantity = $quantities ? (float) ($quantities[$lineId] ?? 0) : $open;

                if ($quantity < 0 || $quantity > $open + 0.0005) {
                    throw new RuntimeException(sprintf('%s: at most %s may still be loaded on %s.', $orderLines[$lineId]->product->name, $this->qty($open), $locked->number));
                }

                if ($quantity > 0) {
                    $rows[$lineId] = $quantity;
                }
            }

            if (! $rows) {
                throw new RuntimeException("Nothing is left to load on {$locked->number}.");
            }

            $this->assertAvailable($warehouse, $rows, $orderLines);

            $loading = LoadingOrder::create([
                'number' => $this->numbers->next('LO'),
                'sales_order_id' => $locked->id,
                'customer_id' => $locked->customer_id,
                'warehouse_id' => $warehouse->id,
                'status' => LoadingOrder::STATUS_OPEN,
                'planned_date' => $data['planned_date'] ?? now()->toDateString(),
                'vehicle_number' => $data['vehicle_number'] ?? null,
                'driver_name' => $data['driver_name'] ?? null,
                'vehicle_id' => $data['vehicle_id'] ?? null,
                'driver_user_id' => $data['driver_user_id'] ?? null,
                'destination' => $data['destination'] ?? $locked->delivery_address,
                'notes' => $data['notes'] ?? null,
                'created_by' => $actor->id,
            ]);

            foreach ($rows as $lineId => $quantity) {
                $loading->lines()->create([
                    'sales_order_line_id' => $lineId,
                    'product_id' => $orderLines[$lineId]->product_id,
                    'quantity_ordered' => $orderLines[$lineId]->quantity_ordered,
                    'quantity_approved' => $quantity,
                ]);
            }

            $this->orders->refreshFulfilment($locked);
            $this->audit->log('dispatch.loading.created', "Loading order {$loading->number} for {$locked->number} from {$warehouse->name}", $loading, actor: $actor);

            return $this->fresh($loading);
        });
    }

    /** @param  array<int, float|string|null>  $loaded  loading line id => quantity actually loaded */
    public function setLoaded(LoadingOrder $loading, array $loaded, User $actor): LoadingOrder
    {
        return DB::transaction(function () use ($loading, $loaded, $actor) {
            $locked = $this->lock($loading);
            SalesOrders::expect($locked->status, [LoadingOrder::STATUS_OPEN], $locked->number, 'changed');

            foreach ($locked->lines()->with('product')->get() as $line) {
                if (! array_key_exists($line->id, $loaded) || $loaded[$line->id] === null || $loaded[$line->id] === '') {
                    continue;
                }

                $quantity = (float) $loaded[$line->id];

                if ($quantity < 0) {
                    throw new RuntimeException("{$line->product->name}: a loaded quantity cannot be negative.");
                }

                if ($quantity > (float) $line->quantity_approved + 0.0005) {
                    throw new RuntimeException(sprintf('%s: %s loaded is more than the %s approved. A truck may carry less than approved, never more.', $line->product->name, $this->qty($quantity), $this->qty((float) $line->quantity_approved)));
                }

                $line->update(['quantity_loaded' => $quantity]);
            }

            $this->audit->log('dispatch.loading.quantities', "Entered loaded quantities on {$locked->number}", $locked, actor: $actor);

            return $this->fresh($locked);
        });
    }

    /** The storekeeper's confirmation: the one moment stock leaves the warehouse. */
    public function confirmLoading(LoadingOrder $loading, User $actor): LoadingOrder
    {
        return DB::transaction(function () use ($loading, $actor) {
            $locked = $this->lock($loading);
            SalesOrders::expect($locked->status, [LoadingOrder::STATUS_OPEN], $locked->number, 'confirmed as loaded');

            if ($locked->stock_document_id) {
                throw new RuntimeException("{$locked->number} has already left the warehouse.");
            }

            $lines = $locked->lines()->with('product.unit')->get();

            if ($lines->contains(fn ($l) => $l->quantity_loaded === null)) {
                throw new RuntimeException("Enter the quantity actually loaded on every line of {$locked->number} first.");
            }

            if ($lines->sum(fn ($l) => (float) $l->quantity_loaded) <= 0) {
                throw new RuntimeException("Nothing was loaded on {$locked->number}. Cancel it instead.");
            }

            $warehouse = Warehouse::query()->findOrFail($locked->warehouse_id);
            $document = $this->stock->create(StockDocument::TYPE_ISSUE, [
                'warehouse_id' => $warehouse->id,
                'document_date' => now()->toDateString(),
                'reference' => $locked->number,
                'reason' => 'Loaded for '.($locked->order?->number ?? 'sales order'),
                'source_type' => LoadingOrder::SOURCE_TYPE,
                'source_id' => $locked->id,
                'contra_account' => 'cogs',
            ], $this->issueLines($warehouse, $lines), $actor);

            $this->stock->post($document, $actor);

            $locked->update([
                'status' => LoadingOrder::STATUS_LOADED,
                'stock_document_id' => $document->id,
                'loaded_by' => $actor->id,
                'loaded_at' => now(),
            ]);

            $this->orders->refreshFulfilment($this->orders->lock($locked->order));
            $this->audit->log('dispatch.loading.confirmed', "Confirmed loading of {$locked->number}; stock issued on {$document->number}", $locked, actor: $actor);

            return $this->fresh($locked);
        });
    }

    public function confirmDriver(LoadingOrder $loading, ?string $name, User $actor): LoadingOrder
    {
        return $this->confirm($loading, 'driver', $name ?: $loading->driver_name, $actor);
    }

    public function confirmSecurity(LoadingOrder $loading, ?string $name, User $actor): LoadingOrder
    {
        return $this->confirm($loading, 'security', $name ?: $actor->name, $actor);
    }

    public function issueDeliveryNote(LoadingOrder $loading, User $actor): LoadingOrder
    {
        return DB::transaction(function () use ($loading, $actor) {
            $locked = $this->lock($loading);
            SalesOrders::expect($locked->status, [LoadingOrder::STATUS_LOADED], $locked->number, 'given a delivery note');

            if ($locked->delivery_note_number) {
                throw new RuntimeException("{$locked->number} already has delivery note {$locked->delivery_note_number}.");
            }

            if (! $locked->driver_confirmed_at || ! $locked->security_confirmed_at) {
                throw new RuntimeException("The driver and security must both confirm the load on {$locked->number} before the delivery note is issued.");
            }

            $locked->update([
                'delivery_note_number' => $this->numbers->next('DN'),
                'delivery_note_issued_at' => now(),
                'delivery_note_issued_by' => $actor->id,
            ]);
            $this->audit->log('dispatch.delivery_note.issued', "Issued delivery note {$locked->delivery_note_number} for {$locked->number}", $locked, actor: $actor);

            return $this->fresh($locked);
        });
    }

    public function issueGatePass(LoadingOrder $loading, User $actor): LoadingOrder
    {
        return DB::transaction(function () use ($loading, $actor) {
            $locked = $this->lock($loading);
            SalesOrders::expect($locked->status, [LoadingOrder::STATUS_LOADED], $locked->number, 'given a gate pass');

            if (! $locked->delivery_note_number) {
                throw new RuntimeException("Issue the delivery note for {$locked->number} before the gate pass.");
            }

            $locked->update([
                'status' => LoadingOrder::STATUS_DISPATCHED,
                'gate_pass_number' => $this->numbers->next('GP'),
                'gate_pass_issued_at' => now(),
                'gate_pass_issued_by' => $actor->id,
            ]);

            $this->orders->refreshFulfilment($this->orders->lock($locked->order));
            $this->audit->log('dispatch.gate_pass.issued', "Issued gate pass {$locked->gate_pass_number}; {$locked->number} left the premises", $locked, actor: $actor);

            return $this->fresh($locked);
        });
    }

    /**
     * Proof of delivery. Anything received short of what was loaded is held
     * as an open discrepancy until someone decides what happened to it.
     *
     * @param  array<string, mixed>  $data  received_by_name, received_date, remark
     * @param  array<int, float|string>  $received  loading line id => quantity received
     */
    public function recordDelivery(LoadingOrder $loading, array $data, array $received, User $actor): LoadingOrder
    {
        return DB::transaction(function () use ($loading, $data, $received, $actor) {
            $locked = $this->lock($loading);
            SalesOrders::expect($locked->status, [LoadingOrder::STATUS_DISPATCHED], $locked->number, 'marked delivered');

            $short = false;
            foreach ($locked->lines()->with('product')->get() as $line) {
                $quantity = array_key_exists($line->id, $received) ? (float) $received[$line->id] : (float) $line->quantity_loaded;

                if ($quantity < 0 || $quantity > (float) $line->quantity_loaded + 0.0005) {
                    throw new RuntimeException(sprintf('%s: the customer can receive between 0 and the %s loaded.', $line->product->name, $this->qty((float) $line->quantity_loaded)));
                }

                $short = $short || $quantity < (float) $line->quantity_loaded - 0.0005;
                $line->update(['quantity_received' => $quantity]);
            }

            $locked->update([
                'status' => LoadingOrder::STATUS_DELIVERED,
                'received_by_name' => mb_substr((string) $data['received_by_name'], 0, 120),
                'received_date' => $data['received_date'] ?? now()->toDateString(),
                'delivery_remark' => isset($data['remark']) ? mb_substr((string) $data['remark'], 0, 500) : null,
                'pod_recorded_by' => $actor->id,
                'pod_recorded_at' => now(),
                'discrepancy_status' => $short ? 'open' : null,
            ]);

            $this->orders->refreshFulfilment($this->orders->lock($locked->order));
            $this->audit->log('dispatch.delivered', "Proof of delivery for {$locked->number}, received by {$locked->received_by_name}".($short ? '; short delivery recorded' : ''), $locked, actor: $actor);

            return $this->fresh($locked);
        });
    }

    /**
     * Decides a short delivery. 'return': the missing goods came back and go
     * into stock through a posted GRN raised from the loading order, at the
     * cost they left at (Dr Inventory, Cr Cost of goods sold). 'write_off':
     * they are lost; their cost moves from cost of goods sold to goods lost in
     * transit, so the margin on what was sold stays true.
     */
    public function resolveDiscrepancy(LoadingOrder $loading, string $decision, string $note, User $actor): LoadingOrder
    {
        return DB::transaction(function () use ($loading, $decision, $note, $actor) {
            $locked = $this->lock($loading);

            if ($locked->discrepancy_status !== 'open') {
                throw new RuntimeException("{$locked->number} has no open delivery discrepancy.");
            }

            $short = $this->shortfall($locked);
            $document = null;

            if ($decision === 'return') {
                $document = $this->stock->create(StockDocument::TYPE_GRN, [
                    'warehouse_id' => $locked->warehouse_id,
                    'reference' => $locked->number,
                    'reason' => "Short delivery returned: {$note}",
                    'source_type' => LoadingOrder::SOURCE_TYPE,
                    'source_id' => $locked->id,
                    'contra_account' => 'cogs',
                ], array_map(fn ($s) => [...$s, 'note' => "Returned from {$locked->number}"], $short), $actor);
                $this->stock->post($document, $actor);
            } else {
                $value = round(array_sum(array_map(fn ($s) => $s['quantity'] * $s['unit_cost'], $short)), 2);

                if ($value > 0 && BusinessConfig::of($this->tenant->company())->postsToLedger()) {
                    $this->journal->post([
                        ['account' => 'transit_losses', 'debit' => $value, 'description' => $locked->number],
                        ['account' => 'cogs', 'credit' => $value, 'description' => $locked->number],
                    ], "Short delivery written off on {$locked->number}", now()->toDateString(), $locked, 'write_off', $actor);
                }
            }

            $locked->update([
                'discrepancy_status' => $decision === 'return' ? 'returned' : 'written_off',
                'discrepancy_note' => mb_substr($note, 0, 500),
                'discrepancy_resolved_by' => $actor->id,
                'discrepancy_resolved_at' => now(),
                'return_document_id' => $document?->id,
            ]);

            $this->audit->log('dispatch.discrepancy.'.($decision === 'return' ? 'returned' : 'written_off'), "Short delivery on {$locked->number} ".($decision === 'return' ? "returned to stock on {$document->number}" : 'written off').": {$note}", $locked, actor: $actor);

            return $this->fresh($locked);
        });
    }

    public function cancel(LoadingOrder $loading, User $actor): LoadingOrder
    {
        return DB::transaction(function () use ($loading, $actor) {
            $locked = $this->lock($loading);
            SalesOrders::expect($locked->status, [LoadingOrder::STATUS_OPEN], $locked->number, 'cancelled');
            $locked->update(['status' => LoadingOrder::STATUS_CANCELLED, 'cancelled_by' => $actor->id]);
            $this->orders->refreshFulfilment($this->orders->lock($locked->order));
            $this->audit->log('dispatch.loading.cancelled', "Cancelled loading order {$locked->number}", $locked, actor: $actor);

            return $this->fresh($locked);
        });
    }

    /**
     * Stock a warehouse can still promise: on hand less what open loading
     * orders there already hold.
     *
     * @param  list<int>  $productIds
     * @return array<int, array<int, array{on_hand: float, reserved: float, available: float}>> product => warehouse => figures
     */
    public function availability(array $productIds): array
    {
        $out = [];
        StockBalance::query()->whereIn('product_id', $productIds)
            ->selectRaw('product_id, warehouse_id, SUM(quantity) as qty')->groupBy('product_id', 'warehouse_id')->get()
            ->each(function ($row) use (&$out) {
                $out[$row->product_id][$row->warehouse_id] = ['on_hand' => (float) $row->qty, 'reserved' => 0.0, 'available' => (float) $row->qty];
            });

        LoadingOrderLine::query()
            ->join('loading_orders', 'loading_orders.id', '=', 'loading_order_lines.loading_order_id')
            ->where('loading_orders.company_id', $this->tenant->id())
            ->where('loading_orders.status', LoadingOrder::STATUS_OPEN)
            ->whereIn('loading_order_lines.product_id', $productIds)
            ->selectRaw('loading_order_lines.product_id, loading_orders.warehouse_id, SUM(loading_order_lines.quantity_approved) as qty')
            ->groupBy('loading_order_lines.product_id', 'loading_orders.warehouse_id')->get()
            ->each(function ($row) use (&$out) {
                $cell = $out[$row->product_id][$row->warehouse_id] ?? ['on_hand' => 0.0, 'reserved' => 0.0, 'available' => 0.0];
                $cell['reserved'] += (float) $row->qty;
                $cell['available'] = round($cell['on_hand'] - $cell['reserved'], 3);
                $out[$row->product_id][$row->warehouse_id] = $cell;
            });

        return $out;
    }

    /* ───────────────────────────────────────────────────────── helpers ── */

    /** @param  array<int, float>  $rows  order line id => quantity */
    private function assertAvailable(Warehouse $warehouse, array $rows, Collection $orderLines): void
    {
        if (BusinessConfig::of($this->tenant->company())->allowsNegativeStock()) {
            return;
        }

        $needed = [];
        foreach ($rows as $lineId => $quantity) {
            $productId = $orderLines[$lineId]->product_id;
            $needed[$productId] = ($needed[$productId] ?? 0) + $quantity;
        }

        $availability = $this->availability(array_keys($needed));

        foreach ($needed as $productId => $quantity) {
            $cell = $availability[$productId][$warehouse->id] ?? ['on_hand' => 0.0, 'reserved' => 0.0, 'available' => 0.0];

            if ($quantity > $cell['available'] + 0.0005) {
                $product = $orderLines->firstWhere('product_id', $productId)->product;
                throw new RuntimeException(sprintf(
                    'Not enough %s in %s: %s available%s, %s needed. The order cannot be loaded from there.',
                    $product->name, $warehouse->name, $this->qty(max(0, $cell['available'])),
                    $cell['reserved'] > 0 ? ' ('.$this->qty($cell['on_hand']).' on hand, '.$this->qty($cell['reserved']).' held for other loading orders)' : '',
                    $this->qty($quantity),
                ));
            }
        }
    }

    /**
     * Lines for the stock issue. Batch-tracked goods leave first-expiry-first,
     * split across as many batches as it takes.
     *
     * @param  Collection<int, LoadingOrderLine>  $lines
     * @return list<array<string, mixed>>
     */
    private function issueLines(Warehouse $warehouse, Collection $lines): array
    {
        $issue = [];
        $allowNegative = BusinessConfig::of($this->tenant->company())->allowsNegativeStock();

        foreach ($lines->groupBy('product_id') as $productId => $group) {
            /** @var Product $product */
            $product = $group->first()->product;
            $quantity = round($group->sum(fn ($l) => (float) $l->quantity_loaded), 3);

            if ($quantity <= 0) {
                continue;
            }

            if ($product->track_serials) {
                throw new RuntimeException("{$product->name} is serial-tracked; issue it unit by unit through a stock issue instead.");
            }

            if (! $product->track_batches) {
                $issue[] = ['product_id' => $product->id, 'quantity' => $quantity];

                continue;
            }

            $batches = StockBalance::query()
                ->where('product_id', $product->id)->where('warehouse_id', $warehouse->id)->where('quantity', '>', 0)
                ->orderByRaw('expiry_date IS NULL')->orderBy('expiry_date')->orderBy('batch_number')
                ->get(['batch_number', 'quantity']);
            $left = $quantity;

            foreach ($batches as $batch) {
                if ($left <= 0.0005) {
                    break;
                }
                $take = min($left, (float) $batch->quantity);
                $issue[] = ['product_id' => $product->id, 'quantity' => round($take, 3), 'batch_number' => $batch->batch_number];
                $left = round($left - $take, 3);
            }

            if ($left > 0.0005) {
                if (! $allowNegative || ! $batches->count()) {
                    throw new RuntimeException(sprintf(
                        'Not enough %s in %s: %s on hand, %s needed.',
                        $product->name, $warehouse->name, $this->qty($quantity - $left), $this->qty($quantity),
                    ));
                }
                $issue[] = ['product_id' => $product->id, 'quantity' => $left, 'batch_number' => $batches->last()->batch_number];
            }
        }

        return $issue;
    }

    /**
     * What did not arrive, priced and batched as it left: each product's
     * shortfall is taken back from the issue's own lines and movements.
     *
     * @return list<array{product_id: int, quantity: float, unit_cost: float, batch_number: ?string, expiry_date: ?string}>
     */
    private function shortfall(LoadingOrder $loading): array
    {
        $missing = [];
        foreach ($loading->lines as $line) {
            $gap = round((float) $line->quantity_loaded - (float) $line->quantity_received, 3);
            if ($gap > 0.0005) {
                $missing[$line->product_id] = ($missing[$line->product_id] ?? 0) + $gap;
            }
        }

        $movements = StockMovement::query()->where('stock_document_id', $loading->stock_document_id)->orderBy('id')->get();
        $rows = [];

        foreach ($missing as $productId => $gap) {
            foreach ($movements->where('product_id', $productId) as $movement) {
                if ($gap <= 0.0005) {
                    break;
                }
                $take = min($gap, abs((float) $movement->quantity));
                $rows[] = [
                    'product_id' => $productId,
                    'quantity' => round($take, 3),
                    'unit_cost' => (float) $movement->unit_cost,
                    'batch_number' => $movement->batch_number !== '' ? $movement->batch_number : null,
                    'expiry_date' => $movement->expiry_date?->toDateString() ?? $this->batchExpiry($productId, (string) $movement->batch_number),
                ];
                $gap = round($gap - $take, 3);
            }
        }

        if (! $rows) {
            throw new RuntimeException("{$loading->number} has nothing missing to decide.");
        }

        return $rows;
    }

    private function batchExpiry(int $productId, string $batch): ?string
    {
        $expiry = StockBalance::query()->where('product_id', $productId)->where('batch_number', $batch)->whereNotNull('expiry_date')->value('expiry_date');

        return $expiry ? substr((string) $expiry, 0, 10) : null;
    }

    private function confirm(LoadingOrder $loading, string $who, ?string $name, User $actor): LoadingOrder
    {
        return DB::transaction(function () use ($loading, $who, $name, $actor) {
            $locked = $this->lock($loading);
            SalesOrders::expect($locked->status, [LoadingOrder::STATUS_LOADED], $locked->number, "confirmed by {$who}");

            if ($locked->{"{$who}_confirmed_at"}) {
                throw new RuntimeException(ucfirst($who)." has already confirmed {$locked->number}.");
            }

            if (blank($name)) {
                throw new RuntimeException("Enter the {$who}'s name.");
            }

            $locked->update([
                "{$who}_confirmed_name" => mb_substr((string) $name, 0, 120),
                "{$who}_confirmed_by" => $actor->id,
                "{$who}_confirmed_at" => now(),
            ]);
            $this->audit->log("dispatch.{$who}.confirmed", ucfirst($who)." ({$name}) confirmed the load on {$locked->number}", $locked, actor: $actor);

            return $this->fresh($locked);
        });
    }

    private function lock(LoadingOrder $loading): LoadingOrder
    {
        return LoadingOrder::query()->whereKey($loading->id)->lockForUpdate()->firstOrFail();
    }

    public function fresh(LoadingOrder $loading): LoadingOrder
    {
        return $loading->fresh([
            'lines.product:id,sku,name,unit_id', 'lines.product.unit:id,code,name', 'lines.orderLine:id,quantity_ordered,quantity_approved',
            'order:id,number,status,payment_mode,total,delivery_address', 'customer:id,code,name,phone,address,city',
            'warehouse:id,code,name,branch', 'stockDocument:id,number,status', 'returnDocument:id,number',
            'creator:id,name', 'loader:id,name', 'driverConfirmer:id,name', 'securityConfirmer:id,name',
            'gatePassIssuer:id,name', 'podRecorder:id,name', 'resolver:id,name',
        ]);
    }

    private function qty(float $value): string
    {
        return rtrim(rtrim(number_format($value, 3, '.', ','), '0'), '.');
    }
}
