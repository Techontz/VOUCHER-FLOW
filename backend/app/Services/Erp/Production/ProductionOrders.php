<?php

namespace App\Services\Erp\Production;

use App\Models\Erp\Product;
use App\Models\Erp\Production\Bom;
use App\Models\Erp\Production\ProductionOrder;
use App\Models\Erp\Production\ProductionReceipt;
use App\Models\Erp\Production\QcCheck;
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
 * Production orders from plan to close.
 *
 *   planned -> released -> in progress -> completed -> closed
 *        \________\______________________-> cancelled (nothing issued yet)
 *
 * Materials leave the store on an issue document charged to work in progress
 * (Dr wip / Cr inventory). Output is recorded as a receipt that waits for a
 * quality check; only the released quantity enters stock, on a GRN credited
 * to work in progress (Dr inventory / Cr wip). A partial receipt is valued at
 * the standard cost fixed at release; the final receipt takes what is left,
 * so the order's output carries its actual cost. Labour and overhead are applied when output is recorded (Dr wip /
 * Cr the applied accounts). Whatever is left on work in progress when the
 * order closes is the production variance, posted once.
 *
 * Every step locks the order row first, so two people acting on the same
 * order queue rather than race.
 */
class ProductionOrders
{
    public function __construct(
        private readonly StockDocuments $documents,
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
        private readonly Boms $boms,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function create(array $data, User $actor): ProductionOrder
    {
        return DB::transaction(function () use ($data, $actor) {
            $bom = $this->bomFor($data);

            $order = ProductionOrder::create([
                ...$this->header($data),
                'number' => $this->numbers->next('PRD'),
                'product_id' => $bom->product_id,
                'bom_id' => $bom->id,
                'status' => ProductionOrder::STATUS_PLANNED,
                'created_by' => $actor->id,
            ]);

            $this->audit->log('production.order.created', "Planned {$order->number}: ".$this->qty($order->planned_quantity)." of {$bom->product->name}", $order, actor: $actor);

            return $order;
        });
    }

    /** @param  array<string, mixed>  $data */
    public function update(ProductionOrder $order, array $data, User $actor): ProductionOrder
    {
        return DB::transaction(function () use ($order, $data, $actor) {
            $locked = $this->lock($order);

            if ($locked->status !== ProductionOrder::STATUS_PLANNED) {
                throw new RuntimeException("{$locked->number} is {$this->label($locked->status)} and can no longer be edited.");
            }

            $bom = $this->bomFor([...$data, 'product_id' => $data['product_id'] ?? $locked->product_id]);
            $locked->update([...$this->header($data), 'product_id' => $bom->product_id, 'bom_id' => $bom->id]);

            $this->audit->log('production.order.updated', "Edited {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    /** Releases a planned order to the floor and fixes its standard cost. */
    public function release(ProductionOrder $order, User $actor): ProductionOrder
    {
        return DB::transaction(function () use ($order, $actor) {
            $locked = $this->lock($order);

            if ($locked->status !== ProductionOrder::STATUS_PLANNED) {
                throw new RuntimeException("{$locked->number} is {$this->label($locked->status)}; only a planned order can be released.");
            }

            $locked->update([
                'status' => ProductionOrder::STATUS_RELEASED,
                'standard_unit_cost' => $this->boms->standardCost($locked->bom)['unit_cost'],
                'released_by' => $actor->id,
                'released_at' => now(),
            ]);

            $this->audit->log('production.order.released', "Released {$locked->number} to production", $locked, actor: $actor);

            return $locked;
        });
    }

    public function cancel(ProductionOrder $order, string $reason, User $actor): ProductionOrder
    {
        return DB::transaction(function () use ($order, $reason, $actor) {
            $locked = $this->lock($order);

            if (! in_array($locked->status, [ProductionOrder::STATUS_PLANNED, ProductionOrder::STATUS_RELEASED], true)) {
                throw new RuntimeException("{$locked->number} is {$this->label($locked->status)} and cannot be cancelled.");
            }

            if ($this->issueDocuments($locked)->isNotEmpty() || $locked->receipts()->exists()) {
                throw new RuntimeException("{$locked->number} already has materials or output recorded and cannot be cancelled.");
            }

            $locked->update([
                'status' => ProductionOrder::STATUS_CANCELLED,
                'cancelled_by' => $actor->id,
                'cancelled_at' => now(),
                'cancel_reason' => mb_substr($reason, 0, 255),
            ]);

            $this->audit->log('production.order.cancelled', "Cancelled {$locked->number} · {$reason}", $locked, actor: $actor);

            return $locked;
        });
    }

    /**
     * Issues materials to the order: one issue document, created and posted
     * in the same transaction, charged to work in progress. A batch-tracked
     * material with no batch named is taken first-expiry-first-out across
     * the batches on hand.
     *
     * @param  list<array{product_id: int, quantity: float|string, batch_number?: ?string}>  $lines
     */
    public function issue(ProductionOrder $order, array $lines, User $actor, ?string $date = null, ?string $note = null): StockDocument
    {
        return DB::transaction(function () use ($order, $lines, $actor, $date, $note) {
            $locked = $this->lock($order);

            if (! in_array($locked->status, [ProductionOrder::STATUS_RELEASED, ProductionOrder::STATUS_IN_PROGRESS], true)) {
                throw new RuntimeException("{$locked->number} is {$this->label($locked->status)}; materials are issued only to a released order or one in progress.");
            }

            $components = $locked->bom->lines()->pluck('product_id')->all();
            $products = Product::query()->whereIn('id', array_column($lines, 'product_id'))->get()->keyBy('id');
            $warehouse = $locked->materialsWarehouse;
            $documentLines = [];

            foreach ($lines as $line) {
                $product = $products[(int) $line['product_id']] ?? throw new RuntimeException('One of the materials is not in this company\'s catalogue.');

                if (! in_array($product->id, $components, true)) {
                    throw new RuntimeException("{$product->name} is not a component of {$locked->number}'s bill of materials.");
                }

                $quantity = round((float) $line['quantity'], 4);

                if ($quantity <= 0) {
                    throw new RuntimeException("{$product->name}: the quantity to issue must be greater than zero.");
                }

                if ($product->track_batches && blank($line['batch_number'] ?? null)) {
                    array_push($documentLines, ...$this->allocateBatches($product, $warehouse, $quantity));
                } else {
                    $documentLines[] = ['product_id' => $product->id, 'quantity' => $quantity, 'batch_number' => $line['batch_number'] ?? null];
                }
            }

            if (! $documentLines) {
                throw new RuntimeException('Add at least one material to issue.');
            }

            $document = $this->documents->create(StockDocument::TYPE_ISSUE, [
                'warehouse_id' => $warehouse->id,
                'document_date' => $date ?? now()->toDateString(),
                'reference' => $locked->number,
                'reason' => $note ?: "Materials for {$locked->number}",
                'source_type' => ProductionOrder::SOURCE,
                'source_id' => $locked->id,
                'contra_account' => 'wip',
            ], $documentLines, $actor);

            $posted = $this->documents->post($document, $actor);

            $locked->update([
                'status' => ProductionOrder::STATUS_IN_PROGRESS,
                'started_at' => $locked->started_at ?? now(),
            ]);
            $this->refreshTotals($locked);

            $this->audit->log('production.order.issued', "Issued materials to {$locked->number} on {$posted->number}", $locked, actor: $actor);

            return $posted;
        });
    }

    /**
     * Records output against the order and applies its labour and overhead.
     * Nothing enters stock here: the receipt waits for its quality check.
     *
     * @param  array<string, mixed>  $data
     */
    public function receive(ProductionOrder $order, array $data, User $actor): ProductionReceipt
    {
        return DB::transaction(function () use ($order, $data, $actor) {
            $locked = $this->lock($order);
            $product = $locked->product;

            if (! in_array($locked->status, [ProductionOrder::STATUS_RELEASED, ProductionOrder::STATUS_IN_PROGRESS], true)) {
                throw new RuntimeException("{$locked->number} is {$this->label($locked->status)}; output is recorded only on a released order or one in progress.");
            }

            if ($locked->receipts()->where('is_final', true)->exists()) {
                throw new RuntimeException("{$locked->number} already has its final receipt.");
            }

            $produced = round((float) $data['produced_quantity'], 3);
            $good = round((float) $data['good_quantity'], 3);
            $rejected = round((float) ($data['rejected_quantity'] ?? 0), 3);
            $wastage = round((float) ($data['wastage_quantity'] ?? 0), 3);

            if ($produced <= 0) {
                throw new RuntimeException('The produced quantity must be greater than zero.');
            }

            if (min($good, $rejected, $wastage) < 0) {
                throw new RuntimeException('Good, rejected and wastage quantities cannot be negative.');
            }

            if (abs($good + $rejected + $wastage - $produced) > 0.0005) {
                throw new RuntimeException(sprintf(
                    'Good (%s), rejected (%s) and wastage (%s) must add up to the produced quantity (%s).',
                    $this->qty($good), $this->qty($rejected), $this->qty($wastage), $this->qty($produced),
                ));
            }

            if (! $product->unit?->allows_decimals && floor($good) != $good) {
                throw new RuntimeException("{$product->name} is counted in whole {$product->unit?->name}s.");
            }

            $batch = filled($data['batch_number'] ?? null) ? trim((string) $data['batch_number']) : null;

            if ($product->track_batches && ! $batch) {
                throw new RuntimeException("{$product->name} is batch-tracked: enter the batch number of this output.");
            }

            if ($product->track_expiry && blank($data['expiry_date'] ?? null)) {
                throw new RuntimeException("{$product->name} tracks expiry: enter the expiry date of this output.");
            }

            if ($batch && ProductionReceipt::query()->where('batch_number', $batch)
                ->whereHas('order', fn ($q) => $q->where('product_id', $product->id))->exists()) {
                throw new RuntimeException("Batch {$batch} of {$product->name} has already been recorded. Each production batch needs its own number.");
            }

            $bom = $locked->bom;
            $output = max((float) $bom->output_quantity, 0.0001);
            $labour = round((float) $bom->labour_cost / $output * $produced, 2);
            $overhead = round((float) $bom->overhead_cost / $output * $produced, 2);

            $receipt = ProductionReceipt::create([
                'production_order_id' => $locked->id,
                'number' => $this->numbers->next('PRC'),
                'receipt_date' => $data['receipt_date'] ?? now()->toDateString(),
                'produced_quantity' => $produced,
                'good_quantity' => $good,
                'rejected_quantity' => $rejected,
                'wastage_quantity' => $wastage,
                'batch_number' => $batch,
                'expiry_date' => $data['expiry_date'] ?? null,
                'is_final' => (bool) ($data['is_final'] ?? false),
                'status' => ProductionReceipt::STATUS_PENDING,
                'conversion_cost' => $labour + $overhead,
                'notes' => $data['notes'] ?? null,
                'recorded_by' => $actor->id,
            ]);

            if ($this->postsToLedger() && $labour + $overhead >= 0.01) {
                $lines = [['account' => 'wip', 'debit' => $labour + $overhead, 'description' => $receipt->number]];

                if ($labour >= 0.01) {
                    $lines[] = ['account' => 'labour_applied', 'credit' => $labour, 'description' => $receipt->number];
                }

                if ($overhead >= 0.01) {
                    $lines[] = ['account' => 'overheads_applied', 'credit' => $overhead, 'description' => $receipt->number];
                }

                $this->journal->post($lines, "Labour and overhead applied to {$locked->number} ({$receipt->number})",
                    $receipt->receipt_date->toDateString(), $receipt, 'conversion', $actor);
            }

            $locked->update([
                'status' => ProductionOrder::STATUS_IN_PROGRESS,
                'started_at' => $locked->started_at ?? now(),
            ]);
            $this->refreshTotals($locked);

            $this->audit->log('production.receipt.recorded', "Recorded {$receipt->number} on {$locked->number}: ".$this->qty($good).' good, '.$this->qty($rejected).' rejected, '.$this->qty($wastage).' wastage', $receipt, actor: $actor);

            return $receipt->load('order');
        });
    }

    /**
     * The quality check. Releasing puts the receipt's good quantity into stock
     * at the order's actual cost per good unit; rejecting keeps it out, and
     * its cost stays on work in progress until the order closes.
     *
     * @param  list<array{name: string, target?: ?string, value?: ?string, passed: bool}>  $parameters
     */
    public function inspect(ProductionReceipt $receipt, string $decision, array $parameters, User $actor, ?string $notes = null): QcCheck
    {
        return DB::transaction(function () use ($receipt, $decision, $parameters, $actor, $notes) {
            $order = $this->lock($receipt->order);
            /** @var ProductionReceipt $locked */
            $locked = ProductionReceipt::query()->whereKey($receipt->id)->lockForUpdate()->firstOrFail();

            if ($locked->status !== ProductionReceipt::STATUS_PENDING) {
                throw new RuntimeException("{$locked->number} has already been {$locked->status}.");
            }

            if (! $parameters) {
                throw new RuntimeException('Record at least one quality parameter.');
            }

            $failed = array_values(array_filter($parameters, fn ($p) => ! ($p['passed'] ?? false)));

            if ($decision === QcCheck::RELEASE && $failed) {
                throw new RuntimeException("{$failed[0]['name']} failed: a batch with a failed parameter cannot be released.");
            }

            if ($decision === QcCheck::RELEASE && (float) $locked->good_quantity <= 0) {
                throw new RuntimeException("{$locked->number} has no good quantity to release.");
            }

            $check = QcCheck::create([
                'production_receipt_id' => $locked->id,
                'production_order_id' => $order->id,
                'decision' => $decision,
                'parameters' => array_map(fn ($p) => [
                    'name' => (string) $p['name'],
                    'target' => isset($p['target']) ? (string) $p['target'] : null,
                    'value' => isset($p['value']) ? (string) $p['value'] : null,
                    'passed' => (bool) ($p['passed'] ?? false),
                ], $parameters),
                'notes' => $notes,
                'inspector_id' => $actor->id,
                'checked_at' => now(),
            ]);

            if ($decision === QcCheck::RELEASE) {
                $this->releaseIntoStock($order, $locked, $actor);
            } else {
                $locked->update(['status' => ProductionReceipt::STATUS_REJECTED, 'released_quantity' => 0]);
                $this->audit->log('production.receipt.rejected', "Rejected {$locked->number}".($locked->batch_number ? " (batch {$locked->batch_number})" : '').' at quality check', $locked, actor: $actor);
            }

            $this->refreshTotals($order);

            if ($locked->is_final) {
                $this->markCompleted($order, $actor);
            }

            return $check->load('receipt', 'inspector:id,name');
        });
    }

    /** Ends production on an order whose output is all recorded and checked. */
    public function complete(ProductionOrder $order, User $actor): ProductionOrder
    {
        return DB::transaction(function () use ($order, $actor) {
            $locked = $this->lock($order);

            if ($locked->status !== ProductionOrder::STATUS_IN_PROGRESS) {
                throw new RuntimeException("{$locked->number} is {$this->label($locked->status)}; only an order in progress can be completed.");
            }

            if (! $locked->receipts()->exists()) {
                throw new RuntimeException("{$locked->number} has no output recorded yet.");
            }

            $this->markCompleted($locked, $actor);

            return $locked;
        });
    }

    /**
     * Clears what is left on work in progress to the production variance
     * account, once, and closes the order for good.
     */
    public function close(ProductionOrder $order, User $actor): ProductionOrder
    {
        return DB::transaction(function () use ($order, $actor) {
            $locked = $this->lock($order);

            if ($locked->status !== ProductionOrder::STATUS_COMPLETED) {
                throw new RuntimeException("{$locked->number} is {$this->label($locked->status)}; only a completed order can be closed.");
            }

            $this->refreshTotals($locked);
            $variance = $locked->wipBalance();

            if ($this->postsToLedger() && abs($variance) >= 0.01) {
                $amount = abs($variance);
                [$debit, $credit] = $variance > 0 ? ['production_variance', 'wip'] : ['wip', 'production_variance'];

                $this->journal->post([
                    ['account' => $debit, 'debit' => $amount, 'description' => $locked->number],
                    ['account' => $credit, 'credit' => $amount, 'description' => $locked->number],
                ], "Production variance on closing {$locked->number}", now()->toDateString(), $locked, 'close', $actor);
            }

            $locked->update([
                'status' => ProductionOrder::STATUS_CLOSED,
                'variance_value' => $variance,
                'closed_by' => $actor->id,
                'closed_at' => now(),
            ]);

            $this->audit->log('production.order.closed', "Closed {$locked->number}; variance ".number_format($variance, 2).' cleared from work in progress', $locked, actor: $actor);

            return $locked;
        });
    }

    /**
     * What the order needs of each component, what has gone to it and what
     * the materials store holds, batch by batch.
     *
     * @return list<array<string, mixed>>
     */
    public function requirements(ProductionOrder $order): array
    {
        $order->loadMissing('bom.lines.product.unit');
        $output = max((float) $order->bom->output_quantity, 0.0001);
        $issued = $this->issuedByProduct($order);
        $produced = (float) $order->produced_quantity;
        $ids = $order->bom->lines->pluck('product_id')->all();

        $balances = StockBalance::query()
            ->whereIn('product_id', $ids)
            ->where('warehouse_id', $order->materials_warehouse_id)
            ->where('quantity', '>', 0)
            ->orderByRaw('expiry_date is null, expiry_date')->orderBy('batch_number')
            ->get()
            ->groupBy('product_id');

        return $order->bom->lines->map(function ($line) use ($order, $output, $issued, $produced, $balances) {
            $perUnit = (float) $line->quantity / $output;
            $scrap = (float) $line->scrap_percent / 100;
            $standard = (float) $order->planned_quantity * $perUnit;
            $required = $standard * (1 + $scrap);
            $issuedQty = $issued[$line->product_id]['quantity'] ?? 0.0;
            $issuedValue = $issued[$line->product_id]['value'] ?? 0.0;
            $held = $balances[$line->product_id] ?? collect();
            $available = (float) $held->sum('quantity');
            $remaining = max(0, $required - $issuedQty);

            // Against what was actually made: anything issued beyond the
            // standard plus its allowance is wastage the recipe did not expect.
            $allowedForOutput = $produced * $perUnit * (1 + $scrap);
            $excess = $produced > 0 ? $issuedQty - $allowedForOutput : 0.0;
            $averageIssueCost = $issuedQty > 0 ? $issuedValue / $issuedQty : 0.0;

            return [
                'product_id' => $line->product_id,
                'product' => $line->product?->only(['id', 'sku', 'name', 'track_batches', 'track_expiry']) + ['unit' => $line->product?->unit?->code, 'allows_decimals' => (bool) $line->product?->unit?->allows_decimals],
                'per_unit' => round($perUnit, 6),
                'scrap_percent' => (float) $line->scrap_percent,
                'standard_quantity' => round($standard, 4),
                'allowance_quantity' => round($standard * $scrap, 4),
                'required_quantity' => round($required, 4),
                'issued_quantity' => round($issuedQty, 4),
                'issued_value' => round($issuedValue, 2),
                'remaining_quantity' => round($remaining, 4),
                'available_quantity' => round($available, 4),
                'shortfall_quantity' => round(max(0, $remaining - $available), 4),
                'sufficient' => $available + 0.00005 >= $remaining,
                'allowed_for_output' => round($allowedForOutput, 4),
                'excess_quantity' => round($excess, 4),
                'excess_value' => round(max(0, $excess) * $averageIssueCost, 2),
                'batches' => $held->map(fn ($b) => [
                    'batch_number' => $b->batch_number,
                    'expiry_date' => $b->expiry_date?->toDateString(),
                    'quantity' => (float) $b->quantity,
                ])->values()->all(),
            ];
        })->values()->all();
    }

    /**
     * Standard against actual, for the cost panel.
     *
     * @return array<string, mixed>
     */
    public function costing(ProductionOrder $order): array
    {
        $released = (float) $order->released_quantity;
        $standardUnit = $order->standard_unit_cost !== null
            ? (float) $order->standard_unit_cost
            : $this->boms->standardCost($order->bom)['unit_cost'];
        $actualTotal = (float) $order->material_cost + (float) $order->conversion_cost;
        $produced = (float) $order->produced_quantity;

        return [
            'standard_unit_cost' => round($standardUnit, 2),
            'standard_total_for_planned' => round($standardUnit * (float) $order->planned_quantity, 2),
            'standard_total_for_released' => round($standardUnit * $released, 2),
            'material_cost' => (float) $order->material_cost,
            'conversion_cost' => (float) $order->conversion_cost,
            'actual_total' => round($actualTotal, 2),
            'actual_unit_cost' => $released > 0 ? round($actualTotal / $released, 2) : null,
            'received_value' => (float) $order->received_value,
            'wip_balance' => $order->status === ProductionOrder::STATUS_CLOSED ? 0.0 : $order->wipBalance(),
            'variance_value' => $order->variance_value !== null ? (float) $order->variance_value : null,
            'variance_against_standard' => $released > 0 ? round($actualTotal - $standardUnit * $released, 2) : null,
            'yield_percent' => $produced > 0 ? round($released / $produced * 100, 1) : null,
        ];
    }

    /** @return Collection<int, StockDocument> posted material issues of the order */
    public function issueDocuments(ProductionOrder $order): Collection
    {
        return StockDocument::query()
            ->where('source_type', ProductionOrder::SOURCE)
            ->where('source_id', $order->id)
            ->where('type', StockDocument::TYPE_ISSUE)
            ->where('status', StockDocument::STATUS_POSTED)
            ->orderBy('id')
            ->get();
    }

    /** Puts a released receipt into stock at the order's actual cost per good unit. */
    private function releaseIntoStock(ProductionOrder $order, ProductionReceipt $receipt, User $actor): void
    {
        $this->refreshTotals($order);
        $good = (float) $receipt->good_quantity;
        $remaining = max(0, $order->wipBalance());

        // The final receipt takes everything left on the order, so its
        // output carries the order's actual cost. An earlier, partial receipt
        // is valued at the standard cost fixed at release (never more than
        // the order has cost so far); the final receipt and the close settle
        // the difference.
        $unitCost = $receipt->is_final
            ? round($remaining / max($good, 0.0001), 2)
            : round(min((float) $order->standard_unit_cost, $remaining / max($good, 0.0001)), 2);

        $document = $this->documents->create(StockDocument::TYPE_GRN, [
            'warehouse_id' => $order->output_warehouse_id,
            'document_date' => min($receipt->receipt_date->toDateString(), now()->toDateString()),
            'reference' => $order->number,
            'reason' => "Output of {$order->number} ({$receipt->number}) released by quality control",
            'source_type' => ProductionOrder::SOURCE,
            'source_id' => $order->id,
            'contra_account' => 'wip',
        ], [[
            'product_id' => $order->product_id,
            'quantity' => $good,
            'unit_cost' => $unitCost,
            'batch_number' => $receipt->batch_number,
            'expiry_date' => $receipt->expiry_date?->toDateString(),
        ]], $actor);

        $posted = $this->documents->post($document, $actor);

        $receipt->update([
            'status' => ProductionReceipt::STATUS_RELEASED,
            'released_quantity' => $good,
            'unit_cost' => $unitCost,
            'value' => round((float) $posted->movements->sum('value'), 2),
            'stock_document_id' => $posted->id,
        ]);

        $this->audit->log('production.receipt.released', "Released {$receipt->number} into {$order->outputWarehouse?->name} on {$posted->number}", $receipt, actor: $actor);
    }

    private function markCompleted(ProductionOrder $order, User $actor): void
    {
        if ($order->receipts()->where('status', ProductionReceipt::STATUS_PENDING)->exists()) {
            throw new RuntimeException("{$order->number} still has output waiting for its quality check.");
        }

        $order->update([
            'status' => ProductionOrder::STATUS_COMPLETED,
            'completed_by' => $actor->id,
            'completed_at' => now(),
        ]);

        $this->audit->log('production.order.completed', "Completed {$order->number}", $order, actor: $actor);
    }

    /**
     * Re-reads the order's totals from the documents and receipts behind
     * them, so the figures on the order can never drift from the ledger.
     */
    public function refreshTotals(ProductionOrder $order): void
    {
        $receipts = $order->receipts()->get();
        $materialCost = -1 * (float) StockMovement::query()
            ->whereIn('stock_document_id', $this->issueDocuments($order)->pluck('id'))
            ->sum('value');
        $receivedValue = (float) StockMovement::query()
            ->whereIn('stock_document_id', $receipts->pluck('stock_document_id')->filter())
            ->sum('value');

        $order->update([
            'produced_quantity' => $receipts->sum(fn ($r) => (float) $r->produced_quantity),
            'good_quantity' => $receipts->sum(fn ($r) => (float) $r->good_quantity),
            'released_quantity' => $receipts->sum(fn ($r) => (float) $r->released_quantity),
            'rejected_quantity' => $receipts->sum(fn ($r) => (float) $r->rejected_quantity
                + ($r->status === ProductionReceipt::STATUS_REJECTED ? (float) $r->good_quantity : 0)),
            'wastage_quantity' => $receipts->sum(fn ($r) => (float) $r->wastage_quantity),
            'material_cost' => round($materialCost, 2),
            'conversion_cost' => round($receipts->sum(fn ($r) => (float) $r->conversion_cost), 2),
            'received_value' => round($receivedValue, 2),
        ]);
    }

    /** @return array<int, array{quantity: float, value: float}> */
    private function issuedByProduct(ProductionOrder $order): array
    {
        return StockMovement::query()
            ->whereIn('stock_document_id', $this->issueDocuments($order)->pluck('id'))
            ->groupBy('product_id')
            ->selectRaw('product_id, -SUM(quantity) as qty, -SUM(value) as val')
            ->get()
            ->mapWithKeys(fn ($r) => [(int) $r->product_id => ['quantity' => (float) $r->qty, 'value' => (float) $r->val]])
            ->all();
    }

    /**
     * Splits a quantity across a batch-tracked material's batches, earliest
     * expiry first, then oldest batch number.
     *
     * @return list<array{product_id: int, quantity: float, batch_number: string}>
     */
    private function allocateBatches(Product $product, Warehouse $warehouse, float $quantity): array
    {
        $batches = StockBalance::query()
            ->where('product_id', $product->id)
            ->where('warehouse_id', $warehouse->id)
            ->where('batch_number', '!=', '')
            ->where('quantity', '>', 0)
            ->orderByRaw('expiry_date is null, expiry_date')->orderBy('batch_number')
            ->get();

        $lines = [];
        $left = $quantity;

        foreach ($batches as $batch) {
            if ($left <= 0.00005) {
                break;
            }

            $take = min($left, (float) $batch->quantity);
            $lines[] = ['product_id' => $product->id, 'quantity' => round($take, 4), 'batch_number' => $batch->batch_number];
            $left = round($left - $take, 4);
        }

        if ($left > 0.00005) {
            $held = $quantity - $left;

            throw new RuntimeException(sprintf(
                'Not enough %s in %s: %s on hand across its batches, %s needed.',
                $product->name, $warehouse->name, $this->qty($held), $this->qty($quantity),
            ));
        }

        return $lines;
    }

    /** @param  array<string, mixed>  $data */
    private function bomFor(array $data): Bom
    {
        $bom = isset($data['bom_id'])
            ? Bom::query()->with('product')->find($data['bom_id'])
            : Bom::query()->with('product')->where('product_id', $data['product_id'] ?? 0)->where('is_active', true)->first();

        if (! $bom) {
            throw new RuntimeException(isset($data['bom_id'])
                ? 'That bill of materials is not in this company\'s records.'
                : 'This product has no active bill of materials. Create or activate one first.');
        }

        if (isset($data['product_id']) && (int) $data['product_id'] !== $bom->product_id) {
            throw new RuntimeException("That bill of materials is for {$bom->product->name}, not the product on this order.");
        }

        if (! $bom->lines()->exists()) {
            throw new RuntimeException("{$bom->name} has no components.");
        }

        return $bom;
    }

    /** @return array<string, mixed> */
    private function header(array $data): array
    {
        if ((float) ($data['planned_quantity'] ?? 0) <= 0) {
            throw new RuntimeException('The planned quantity must be greater than zero.');
        }

        $start = $data['planned_start'] ?? now()->toDateString();
        $end = $data['planned_end'] ?? $start;

        if ($end < $start) {
            throw new RuntimeException('The planned end cannot be before the planned start.');
        }

        return [
            'planned_quantity' => $data['planned_quantity'],
            'materials_warehouse_id' => $data['materials_warehouse_id'],
            'output_warehouse_id' => $data['output_warehouse_id'],
            'planned_start' => $start,
            'planned_end' => $end,
            'reference' => $data['reference'] ?? null,
            'notes' => $data['notes'] ?? null,
        ];
    }

    private function lock(ProductionOrder $order): ProductionOrder
    {
        return ProductionOrder::query()->whereKey($order->id)->lockForUpdate()->firstOrFail();
    }

    private function postsToLedger(): bool
    {
        return BusinessConfig::of($this->tenant->company())->postsToLedger();
    }

    private function label(string $status): string
    {
        return str_replace('_', ' ', $status);
    }

    private function qty(float|string|null $value): string
    {
        return rtrim(rtrim(number_format((float) $value, 3, '.', ','), '0'), '.');
    }
}
