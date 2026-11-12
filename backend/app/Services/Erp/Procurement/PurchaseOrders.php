<?php

namespace App\Services\Erp\Procurement;

use App\Models\Erp\Procurement\ProcurementSetting;
use App\Models\Erp\Procurement\PurchaseOrder;
use App\Models\Erp\Procurement\PurchaseOrderLine;
use App\Models\Erp\Procurement\PurchaseReceipt;
use App\Models\Erp\Procurement\PurchaseRequisition;
use App\Models\Erp\Procurement\PurchaseRfq;
use App\Models\Erp\Procurement\SupplierQuotation;
use App\Models\Erp\StockDocument;
use App\Models\Erp\Supplier;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\StockDocuments;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Purchase orders from draft to closed, and receiving against them.
 *
 * Goods are received through the core GRN: a stock document is created and
 * posted with source_type 'purchase_order', so stock and its value move
 * exactly as any other receipt (Dr Inventory, Cr GRNI). This service only
 * keeps the received quantity per order line, and refuses to receive more
 * than was ordered unless the company allows a tolerance. Services are
 * confirmed, not received: nothing moves in stock.
 */
class PurchaseOrders
{
    public const RELATIONS = [
        'lines.product:id,sku,name,unit_id,track_batches,track_expiry,track_serials', 'lines.product.unit:id,code',
        'lines.expenseAccount:id,code,name', 'supplier:id,code,name,payment_terms_days', 'warehouse:id,code,name',
        'requisition:id,number,status', 'quotation:id,purchase_rfq_id,reference', 'creator:id,name',
        'approvals.user:id,name,role', 'receipts.lines', 'receipts.receiver:id,name', 'receipts.stockDocument:id,number,status',
        'invoices:id,number,supplier_invoice_number,purchase_order_id,status,total,amount_paid,match_status',
    ];

    public function __construct(
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly Approvals $approvals,
        private readonly Requisitions $requisitions,
        private readonly StockDocuments $stock,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function create(array $data, User $actor): PurchaseOrder
    {
        return DB::transaction(function () use ($data, $actor) {
            $quotation = null;
            $requisition = null;
            $lines = $data['lines'] ?? [];

            if (! empty($data['supplier_quotation_id'])) {
                $quotation = SupplierQuotation::query()->with('lines.rfqLine', 'rfq')->findOrFail($data['supplier_quotation_id']);

                if ($quotation->status !== SupplierQuotation::STATUS_SELECTED || $quotation->rfq?->status !== PurchaseRfq::STATUS_AWARDED) {
                    throw new RuntimeException('Only the quotation selected on an awarded request for quotation can become an order.');
                }

                if (PurchaseOrder::query()->where('supplier_quotation_id', $quotation->id)->where('status', '!=', PurchaseOrder::STATUS_CANCELLED)->exists()) {
                    throw new RuntimeException('An order has already been raised from that quotation.');
                }

                $data['supplier_id'] = $quotation->supplier_id;
                $data['purchase_requisition_id'] ??= $quotation->rfq->purchase_requisition_id;
                $data['payment_terms'] ??= $quotation->payment_terms;

                if (! $lines) {
                    $lines = $quotation->lines->map(fn ($l) => [
                        'purchase_requisition_line_id' => $l->rfqLine->purchase_requisition_line_id,
                        'line_type' => $l->rfqLine->line_type, 'product_id' => $l->rfqLine->product_id,
                        'description' => $l->rfqLine->description, 'quantity' => (float) $l->rfqLine->quantity,
                        'unit_price' => (float) $l->unit_price, 'vat_rate' => (float) $l->vat_rate,
                        'expense_account_id' => $l->rfqLine->expense_account_id,
                    ])->all();
                }
            }

            if (! empty($data['purchase_requisition_id'])) {
                $requisition = PurchaseRequisition::query()->findOrFail($data['purchase_requisition_id']);
                $this->requisitions->markOrdered($requisition, $actor);
            }

            $supplier = Supplier::query()->whereKey($data['supplier_id'] ?? 0)->where('is_active', true)->first()
                ?? throw new RuntimeException('Choose an active supplier.');

            $order = PurchaseOrder::create([
                ...$this->header($data),
                'number' => $this->numbers->next('LPO'),
                'supplier_id' => $supplier->id,
                'purchase_requisition_id' => $requisition?->id,
                'supplier_quotation_id' => $quotation?->id,
                'payment_terms' => $data['payment_terms'] ?? ($supplier->payment_terms_days ? "{$supplier->payment_terms_days} days" : null),
                'status' => PurchaseOrder::STATUS_DRAFT,
                'created_by' => $actor->id,
            ]);

            $this->writeLines($order, $lines, (bool) $requisition);
            $this->audit->log('procurement.order.created', "Raised purchase order {$order->number} to {$supplier->name}", $order, actor: $actor);

            return $order->fresh(self::RELATIONS);
        });
    }

    /** @param  array<string, mixed>  $data */
    public function update(PurchaseOrder $order, array $data, User $actor): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $data, $actor) {
            $locked = $this->lock($order);
            $this->assertStatus($locked, [PurchaseOrder::STATUS_DRAFT], 'edited');

            $locked->update($this->header($data));
            $locked->lines()->delete();
            $this->writeLines($locked, $data['lines'] ?? [], (bool) $locked->purchase_requisition_id);
            $this->audit->log('procurement.order.updated', "Edited purchase order {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function submit(PurchaseOrder $order, User $actor): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $actor) {
            $locked = $this->lock($order);
            $this->assertStatus($locked, [PurchaseOrder::STATUS_DRAFT], 'submitted');

            $locked->update([
                'status' => PurchaseOrder::STATUS_SUBMITTED,
                'submitted_at' => now(),
                'approvals_required' => $this->approvals->required((float) $locked->total),
            ]);
            $this->audit->log('procurement.order.submitted', "Submitted purchase order {$locked->number} for approval", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function approve(PurchaseOrder $order, User $actor, ?string $comment): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $actor, $comment) {
            $locked = $this->lock($order);
            $this->assertStatus($locked, [PurchaseOrder::STATUS_SUBMITTED], 'approved');

            $done = $this->approvals->approve($locked, $locked->approvals_required, $locked->created_by, $actor, $comment);

            if ($done) {
                $locked->update(['status' => PurchaseOrder::STATUS_APPROVED, 'approved_at' => now()]);
            }

            $this->audit->log('procurement.order.approved', $done
                ? "Approved purchase order {$locked->number}"
                : "Gave the first of two approvals to purchase order {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    /** A rejected order goes back to draft for its author to correct. */
    public function reject(PurchaseOrder $order, User $actor, string $comment): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $actor, $comment) {
            $locked = $this->lock($order);
            $this->assertStatus($locked, [PurchaseOrder::STATUS_SUBMITTED], 'rejected');

            $this->approvals->reject($locked, $actor, $comment);
            $locked->update(['status' => PurchaseOrder::STATUS_DRAFT, 'submitted_at' => null]);
            $this->audit->log('procurement.order.rejected', "Returned purchase order {$locked->number} to draft · {$comment}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function send(PurchaseOrder $order, User $actor): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $actor) {
            $locked = $this->lock($order);
            $this->assertStatus($locked, [PurchaseOrder::STATUS_APPROVED], 'sent');

            $locked->update(['status' => PurchaseOrder::STATUS_SENT, 'sent_at' => now()]);
            $this->audit->log('procurement.order.sent', "Sent purchase order {$locked->number} to the supplier", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    /**
     * Receives goods against the order through a posted GRN.
     *
     * @param  array<string, mixed>  $data  warehouse_id, received_date, delivery_note, notes, lines[{purchase_order_line_id, quantity, batch_number, expiry_date, serial_number}]
     */
    public function receive(PurchaseOrder $order, array $data, User $actor): PurchaseReceipt
    {
        return DB::transaction(function () use ($order, $data, $actor) {
            $locked = $this->lock($order);
            $this->assertReceivable($locked);

            $warehouseId = (int) ($data['warehouse_id'] ?? $locked->warehouse_id);
            $warehouse = Warehouse::query()->whereKey($warehouseId)->where('is_active', true)->first()
                ?? throw new RuntimeException('Choose the active store the goods are received into.');

            $wanted = $this->wantedLines($locked, $data['lines'] ?? [], false);
            $date = $data['received_date'] ?? now()->toDateString();

            $document = $this->stock->create(StockDocument::TYPE_GRN, [
                'document_date' => $date,
                'warehouse_id' => $warehouse->id,
                'supplier_id' => $locked->supplier_id,
                'reference' => mb_substr(trim($locked->number.' '.($data['delivery_note'] ?? '')), 0, 80),
                'reason' => "Received against {$locked->number}",
                'notes' => $data['notes'] ?? null,
                'source_type' => 'purchase_order',
                'source_id' => $locked->id,
            ], array_map(fn ($w) => [
                'product_id' => $w['line']->product_id,
                'quantity' => $w['quantity'],
                // Stock comes in at the ordered price; any difference on the invoice is a price variance.
                'unit_cost' => (float) $w['line']->unit_price,
                'batch_number' => $w['batch_number'],
                'expiry_date' => $w['expiry_date'],
                'serial_number' => $w['serial_number'],
                'note' => $w['line']->description,
            ], $wanted), $actor);

            $document = $this->stock->post($document, $actor);
            $documentLines = $document->lines()->orderBy('id')->get()->values();

            $receipt = PurchaseReceipt::create([
                'purchase_order_id' => $locked->id,
                'kind' => PurchaseReceipt::KIND_GOODS,
                'number' => $document->number,
                'stock_document_id' => $document->id,
                'received_date' => $date,
                'delivery_note' => $data['delivery_note'] ?? null,
                'notes' => $data['notes'] ?? null,
                'received_by' => $actor->id,
            ]);

            $this->recordReceiptLines($receipt, $wanted, fn (int $i) => $documentLines[$i]->id ?? null);
            $this->refreshReceivedStatus($locked);
            $this->audit->log('procurement.order.received', "Received goods against {$locked->number} with {$document->number}", $locked, actor: $actor);

            return $receipt->fresh(['lines', 'stockDocument:id,number,status']);
        });
    }

    /**
     * Confirms that services on the order were delivered. No stock moves; the
     * confirmation is what the supplier's invoice is matched against.
     *
     * @param  array<string, mixed>  $data
     */
    public function confirmService(PurchaseOrder $order, array $data, User $actor): PurchaseReceipt
    {
        return DB::transaction(function () use ($order, $data, $actor) {
            $locked = $this->lock($order);
            $this->assertReceivable($locked);

            $wanted = $this->wantedLines($locked, $data['lines'] ?? [], true);

            $receipt = PurchaseReceipt::create([
                'purchase_order_id' => $locked->id,
                'kind' => PurchaseReceipt::KIND_SERVICE,
                'number' => $this->numbers->next('SVC'),
                'received_date' => $data['received_date'] ?? now()->toDateString(),
                'delivery_note' => $data['delivery_note'] ?? null,
                'notes' => $data['notes'] ?? null,
                'received_by' => $actor->id,
            ]);

            $this->recordReceiptLines($receipt, $wanted, fn () => null);
            $this->refreshReceivedStatus($locked);
            $this->audit->log('procurement.order.service_confirmed', "Confirmed services on {$locked->number} with {$receipt->number}", $locked, actor: $actor);

            return $receipt->fresh('lines');
        });
    }

    public function close(PurchaseOrder $order, User $actor): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $actor) {
            $locked = $this->lock($order);
            $this->assertStatus($locked, [PurchaseOrder::STATUS_PARTIALLY_RECEIVED, PurchaseOrder::STATUS_RECEIVED], 'closed');

            $locked->update(['status' => PurchaseOrder::STATUS_CLOSED, 'closed_at' => now()]);
            $this->audit->log('procurement.order.closed', "Closed purchase order {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function cancel(PurchaseOrder $order, string $reason, User $actor): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $reason, $actor) {
            $locked = $this->lock($order);
            if ($locked->receipts()->exists() && ! in_array($locked->status, [PurchaseOrder::STATUS_CLOSED, PurchaseOrder::STATUS_CANCELLED], true)) {
                throw new RuntimeException("Goods have been received against {$locked->number}; close it instead of cancelling it.");
            }

            $this->assertStatus($locked, [PurchaseOrder::STATUS_DRAFT, PurchaseOrder::STATUS_SUBMITTED, PurchaseOrder::STATUS_APPROVED, PurchaseOrder::STATUS_SENT], 'cancelled');

            $locked->update(['status' => PurchaseOrder::STATUS_CANCELLED, 'cancelled_at' => now(), 'cancel_reason' => mb_substr($reason, 0, 255)]);
            $this->audit->log('procurement.order.cancelled', "Cancelled purchase order {$locked->number} · {$reason}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    /** Closes an order once everything on it has been received and invoiced. */
    public function closeIfComplete(PurchaseOrder $order): void
    {
        $lines = $order->lines()->get();

        $complete = $order->status === PurchaseOrder::STATUS_RECEIVED && $lines->every(
            fn (PurchaseOrderLine $l) => (float) $l->invoiced_quantity + 0.0005 >= (float) $l->received_quantity
        );

        if ($complete) {
            $order->update(['status' => PurchaseOrder::STATUS_CLOSED, 'closed_at' => now()]);
        }
    }

    /**
     * Checks each requested receipt line against what is still outstanding.
     *
     * @param  list<array<string, mixed>>  $requested
     * @return list<array{line: PurchaseOrderLine, quantity: float, batch_number: ?string, expiry_date: ?string, serial_number: ?string}>
     */
    private function wantedLines(PurchaseOrder $order, array $requested, bool $services): array
    {
        $lines = $order->lines()->with('product')->lockForUpdate()->get()->keyBy('id');
        $tolerance = (float) ProcurementSetting::current()->receipt_tolerance_percent;
        $wanted = [];
        $pending = [];

        foreach ($requested as $row) {
            $quantity = round((float) ($row['quantity'] ?? 0), 3);

            if ($quantity == 0.0) {
                continue;
            }

            $line = $lines[$row['purchase_order_line_id'] ?? 0] ?? throw new RuntimeException("One of the lines does not belong to {$order->number}.");

            if ($line->isService() !== $services) {
                throw new RuntimeException($services
                    ? "{$line->description} is a stock line: receive it as goods."
                    : "{$line->description} is a service: confirm it instead of receiving it into stock.");
            }

            if ($quantity < 0) {
                throw new RuntimeException("{$line->description}: the quantity received must be greater than zero.");
            }

            $pending[$line->id] = ($pending[$line->id] ?? 0) + $quantity;
            $allowed = round((float) $line->quantity * (1 + $tolerance / 100), 3);
            $after = round((float) $line->received_quantity + $pending[$line->id], 3);

            if ($after > $allowed + 0.0005) {
                throw new RuntimeException(sprintf(
                    'Cannot receive more than was ordered: %s ordered %s, %s already received, %s more would make %s.',
                    $line->description, $this->qty($line->quantity), $this->qty($line->received_quantity), $this->qty($pending[$line->id]), $this->qty($after),
                ).($tolerance > 0 ? " The tolerance allows up to {$this->qty($allowed)}." : ''));
            }

            $wanted[] = [
                'line' => $line,
                'quantity' => $quantity,
                'batch_number' => $row['batch_number'] ?? null,
                'expiry_date' => $row['expiry_date'] ?? null,
                'serial_number' => $row['serial_number'] ?? null,
            ];
        }

        if (! $wanted) {
            throw new RuntimeException($services ? 'Enter the quantity of service delivered on at least one line.' : 'Enter the quantity received on at least one line.');
        }

        return $wanted;
    }

    /** @param  list<array<string, mixed>>  $wanted */
    private function recordReceiptLines(PurchaseReceipt $receipt, array $wanted, callable $documentLine): void
    {
        $value = 0.0;

        foreach ($wanted as $i => $w) {
            $lineValue = Lines::money($w['quantity'] * (float) $w['line']->unit_price);
            $value += $lineValue;

            $receipt->lines()->create([
                'purchase_order_line_id' => $w['line']->id,
                'stock_document_line_id' => $documentLine($i),
                'quantity' => $w['quantity'],
                'unit_cost' => $w['line']->unit_price,
                'value' => $lineValue,
            ]);

            $w['line']->increment('received_quantity', $w['quantity']);
        }

        $receipt->update(['value' => Lines::money($value)]);
    }

    private function refreshReceivedStatus(PurchaseOrder $order): void
    {
        $lines = $order->lines()->get();
        $all = $lines->every(fn (PurchaseOrderLine $l) => (float) $l->received_quantity + 0.0005 >= (float) $l->quantity);

        $order->update($all
            ? ['status' => PurchaseOrder::STATUS_RECEIVED, 'received_at' => now()]
            : ['status' => PurchaseOrder::STATUS_PARTIALLY_RECEIVED]);
    }

    /** @return array<string, mixed> */
    private function header(array $data): array
    {
        $warehouse = $data['warehouse_id'] ?? null;

        if ($warehouse && ! Warehouse::query()->whereKey($warehouse)->exists()) {
            throw new RuntimeException('Choose a store from this company.');
        }

        return [
            'warehouse_id' => $warehouse,
            'order_date' => $data['order_date'] ?? now()->toDateString(),
            'expected_date' => $data['expected_date'] ?? null,
            'notes' => $data['notes'] ?? null,
            ...(array_key_exists('payment_terms', $data) ? ['payment_terms' => $data['payment_terms']] : []),
        ];
    }

    /** @param  list<array<string, mixed>>  $lines */
    private function writeLines(PurchaseOrder $order, array $lines, bool $keepRequisitionLinks): void
    {
        if (! $lines) {
            throw new RuntimeException('Add at least one line.');
        }

        $subtotal = 0.0;
        $vat = 0.0;
        $defaultRate = (float) ProcurementSetting::current()->default_vat_rate;

        foreach (array_values($lines) as $i => $line) {
            $quantity = round((float) ($line['quantity'] ?? 0), 3);
            $price = (float) ($line['unit_price'] ?? -1);

            if ($quantity <= 0) {
                throw new RuntimeException('Line '.($i + 1).': the quantity must be greater than zero.');
            }

            if ($price < 0) {
                throw new RuntimeException('Line '.($i + 1).': enter the unit price agreed with the supplier.');
            }

            $rate = isset($line['vat_rate']) && $line['vat_rate'] !== '' ? (float) $line['vat_rate'] : $defaultRate;
            $amount = Lines::money($quantity * $price);
            $lineVat = Lines::money($amount * $rate / 100);
            $subtotal += $amount;
            $vat += $lineVat;

            $order->lines()->create([
                ...Lines::normalise($line, $i),
                'purchase_requisition_line_id' => $keepRequisitionLinks ? Lines::requisitionLine($order->purchase_requisition_id, $line['purchase_requisition_line_id'] ?? null) : null,
                'quantity' => $quantity,
                'unit_price' => $price,
                'vat_rate' => $rate,
                'amount' => $amount,
                'vat_amount' => $lineVat,
            ]);
        }

        $order->update(['subtotal' => Lines::money($subtotal), 'vat_amount' => Lines::money($vat), 'total' => Lines::money($subtotal + $vat)]);
    }

    private function assertReceivable(PurchaseOrder $order): void
    {
        if (! in_array($order->status, PurchaseOrder::RECEIVABLE, true)) {
            throw new RuntimeException("Purchase order {$order->number} is {$order->status}; goods can be received only against an approved or sent order.");
        }
    }

    private function lock(PurchaseOrder $order): PurchaseOrder
    {
        return PurchaseOrder::query()->whereKey($order->id)->lockForUpdate()->firstOrFail();
    }

    /** @param  list<string>  $allowed */
    private function assertStatus(PurchaseOrder $order, array $allowed, string $verb): void
    {
        if (! in_array($order->status, $allowed, true)) {
            throw new RuntimeException("Purchase order {$order->number} is {$order->status} and cannot be {$verb}.");
        }
    }

    private function qty(float|string $value): string
    {
        return rtrim(rtrim(number_format((float) $value, 3, '.', ''), '0'), '.');
    }
}
