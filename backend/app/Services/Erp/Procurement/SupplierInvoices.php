<?php

namespace App\Services\Erp\Procurement;

use App\Models\Erp\Account;
use App\Models\Erp\Procurement\ProcurementSetting;
use App\Models\Erp\Procurement\PurchaseOrder;
use App\Models\Erp\Procurement\PurchaseOrderLine;
use App\Models\Erp\Procurement\SupplierInvoice;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Supplier invoices and the three-way match.
 *
 * Each invoice line is held against its order line (what was agreed) and what
 * was received and not yet invoiced (what arrived). A price or quantity that
 * strays beyond the company's tolerance flags the line, and a flagged invoice
 * needs procurement.approve before it can be posted.
 *
 * Posting, once, under a row lock and a source-keyed journal:
 *   stock line    Dr GRNI (received quantity at the order price)
 *                 Dr/Cr Purchase price variance (the price difference)
 *                 Dr Purchase quantity variance (anything invoiced beyond what was received)
 *   service line  Dr the line's expense account
 *   all           Dr VAT input,  Cr Accounts payable (the invoice total)
 */
class SupplierInvoices
{
    public const RELATIONS = [
        'lines.orderLine:id,purchase_order_id,description,quantity,unit_price,received_quantity,invoiced_quantity,line_type,product_id',
        'lines.expenseAccount:id,code,name', 'supplier:id,code,name,payment_terms_days', 'order:id,number,status,supplier_id',
        'approvals.user:id,name,role', 'allocations.payment:id,number,payment_date,status,amount', 'journal:id,number,status',
        'creator:id,name', 'poster:id,name', 'varianceApprover:id,name',
    ];

    public function __construct(
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly JournalPoster $journal,
        private readonly TenantContext $tenant,
        private readonly PurchaseOrders $orders,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function create(array $data, User $actor): SupplierInvoice
    {
        return $this->guardDuplicate(fn () => DB::transaction(function () use ($data, $actor) {
            $order = $this->invoiceableOrder((int) $data['purchase_order_id']);
            $this->assertNewNumber($order->supplier_id, $data['supplier_invoice_number']);

            $invoice = SupplierInvoice::create([
                ...$this->header($data, $order),
                'number' => $this->numbers->next('SINV'),
                'supplier_id' => $order->supplier_id,
                'purchase_order_id' => $order->id,
                'status' => SupplierInvoice::STATUS_DRAFT,
                'created_by' => $actor->id,
            ]);

            $this->writeLines($invoice, $order, $data['lines'] ?? []);
            $this->audit->log('procurement.invoice.created', "Recorded supplier invoice {$invoice->supplier_invoice_number} as {$invoice->number}", $invoice, actor: $actor);

            return $invoice->fresh(self::RELATIONS);
        }), $data);
    }

    /** @param  array<string, mixed>  $data */
    public function update(SupplierInvoice $invoice, array $data, User $actor): SupplierInvoice
    {
        return $this->guardDuplicate(fn () => DB::transaction(function () use ($invoice, $data, $actor) {
            $locked = $this->lock($invoice);
            $this->assertStatus($locked, [SupplierInvoice::STATUS_DRAFT, SupplierInvoice::STATUS_AWAITING_APPROVAL, SupplierInvoice::STATUS_APPROVED], 'edited');

            if ($data['supplier_invoice_number'] !== $locked->supplier_invoice_number) {
                $this->assertNewNumber($locked->supplier_id, $data['supplier_invoice_number']);
            }

            $order = $this->invoiceableOrder($locked->purchase_order_id);
            // Any edit asks for the match, and any approval of it, again.
            $locked->update([...$this->header($data, $order), 'variance_approved_by' => null, 'variance_approved_at' => null]);
            $locked->lines()->delete();
            $this->writeLines($locked, $order, $data['lines'] ?? []);
            $this->audit->log('procurement.invoice.updated', "Edited supplier invoice {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        }), $data);
    }

    /** Accepts the variances on a flagged invoice so it can be posted. */
    public function approveVariance(SupplierInvoice $invoice, User $actor, ?string $comment): SupplierInvoice
    {
        return DB::transaction(function () use ($invoice, $actor, $comment) {
            $locked = $this->lock($invoice);
            $this->assertStatus($locked, [SupplierInvoice::STATUS_AWAITING_APPROVAL], 'approved');

            if ($locked->created_by === $actor->id) {
                throw new RuntimeException("You recorded {$locked->number}, so someone else must approve its variance.");
            }

            app(Approvals::class)->approve($locked, 1, $locked->created_by, $actor, $comment);
            $locked->update(['status' => SupplierInvoice::STATUS_APPROVED, 'variance_approved_by' => $actor->id, 'variance_approved_at' => now()]);
            $this->audit->log('procurement.invoice.variance_approved', "Approved the match variance on {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function post(SupplierInvoice $invoice, User $actor): SupplierInvoice
    {
        return DB::transaction(function () use ($invoice, $actor) {
            $locked = $this->lock($invoice);

            if ($locked->status === SupplierInvoice::STATUS_POSTED) {
                throw new RuntimeException("{$locked->number} has already been posted.");
            }

            if ($locked->status === SupplierInvoice::STATUS_AWAITING_APPROVAL) {
                throw new RuntimeException("{$locked->number} does not match its order and receipts within tolerance; it needs approval before it can be posted.");
            }

            $this->assertStatus($locked, [SupplierInvoice::STATUS_DRAFT, SupplierInvoice::STATUS_APPROVED], 'posted');

            $lines = $locked->lines()->get();
            $orderLines = PurchaseOrderLine::query()->whereIn('id', $lines->pluck('purchase_order_line_id'))->lockForUpdate()->get()->keyBy('id');

            // Another invoice may have been posted against the same receipts since this one was matched.
            foreach ($lines as $line) {
                $orderLine = $orderLines[$line->purchase_order_line_id];

                if (round($orderLine->matchable(), 3) < round((float) $line->matchable_quantity, 3) - 0.0005 && $locked->status !== SupplierInvoice::STATUS_APPROVED) {
                    throw new RuntimeException("{$line->description}: another invoice has been posted against these receipts since {$locked->number} was matched. Open it and save it again to re-match.");
                }
            }

            $entry = null;

            if (BusinessConfig::of($this->tenant->company())->postsToLedger()) {
                $entry = $this->journal->post(
                    $this->journalLines($locked, $lines, $orderLines),
                    "Supplier invoice {$locked->supplier_invoice_number} ({$locked->number})",
                    $locked->invoice_date->toDateString(),
                    $locked,
                    'post',
                    $actor,
                );
            }

            foreach ($lines as $line) {
                $orderLines[$line->purchase_order_line_id]->increment('invoiced_quantity', (float) $line->quantity);
            }

            $locked->update([
                'status' => SupplierInvoice::STATUS_POSTED,
                'posted_by' => $actor->id,
                'posted_at' => now(),
                'journal_entry_id' => $entry?->id,
            ]);

            $this->orders->closeIfComplete(PurchaseOrder::query()->lockForUpdate()->findOrFail($locked->purchase_order_id));
            $this->audit->log('procurement.invoice.posted', "Posted supplier invoice {$locked->number}".($entry ? " as journal {$entry->number}" : ''), $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function cancel(SupplierInvoice $invoice, User $actor): SupplierInvoice
    {
        return DB::transaction(function () use ($invoice, $actor) {
            $locked = $this->lock($invoice);
            $this->assertStatus($locked, [SupplierInvoice::STATUS_DRAFT, SupplierInvoice::STATUS_AWAITING_APPROVAL, SupplierInvoice::STATUS_APPROVED], 'cancelled');

            $locked->update(['status' => SupplierInvoice::STATUS_CANCELLED]);
            $this->audit->log('procurement.invoice.cancelled', "Cancelled supplier invoice {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    /**
     * The journal, built so it balances by construction: every line's
     * amount is split into received value, quantity excess and price
     * difference, which add back to the amount to the cent.
     *
     * @return list<array<string, mixed>>
     */
    private function journalLines(SupplierInvoice $invoice, $lines, $orderLines): array
    {
        $byAccount = [];
        $add = function (array $key, float $amount) use (&$byAccount) {
            $id = json_encode($key);
            $byAccount[$id] = ['key' => $key, 'amount' => round(($byAccount[$id]['amount'] ?? 0) + $amount, 2)];
        };
        $fallbackExpense = Account::query()->where('system_key', 'other_expenses')->value('id');

        foreach ($lines as $line) {
            $amount = (float) $line->amount;

            if ($line->line_type === 'service') {
                $account = $line->expense_account_id ?: $orderLines[$line->purchase_order_line_id]->expense_account_id ?: $fallbackExpense;
                $account ? $add(['account_id' => (int) $account], $amount) : $add(['account' => 'other_expenses'], $amount);

                continue;
            }

            $quantity = (float) $line->quantity;
            $matched = max(0.0, min($quantity, (float) $line->matchable_quantity));
            $atOrder = Lines::money($quantity * (float) $line->order_unit_price);
            $received = Lines::money($matched * (float) $line->order_unit_price);

            $add(['account' => 'grni'], $received);
            $add(['account' => 'purchase_quantity_variance'], round($atOrder - $received, 2));
            $add(['account' => 'purchase_price_variance'], round($amount - $atOrder, 2));
        }

        $add(['account' => 'vat_input'], (float) $invoice->vat_amount);

        $journal = [];
        foreach ($byAccount as ['key' => $key, 'amount' => $amount]) {
            if (abs($amount) < 0.005) {
                continue;
            }

            $journal[] = [...$key, ...($amount > 0 ? ['debit' => $amount] : ['credit' => -$amount]), 'description' => $invoice->number];
        }

        $journal[] = ['account' => 'payable', 'credit' => (float) $invoice->total, 'description' => "{$invoice->number} · {$invoice->supplier_invoice_number}"];

        return $journal;
    }

    /**
     * Writes the lines with their match against the order and receipts.
     *
     * @param  list<array<string, mixed>>  $lines
     */
    private function writeLines(SupplierInvoice $invoice, PurchaseOrder $order, array $lines): void
    {
        if (! $lines) {
            throw new RuntimeException('Add at least one line.');
        }

        $settings = ProcurementSetting::current();
        $priceTolerance = (float) $settings->price_tolerance_percent;
        $quantityTolerance = (float) $settings->quantity_tolerance_percent;
        $orderLines = $order->lines()->get()->keyBy('id');
        $subtotal = 0.0;
        $vat = 0.0;
        $flagged = false;

        foreach (array_values($lines) as $i => $row) {
            $n = $i + 1;
            $orderLine = $orderLines[$row['purchase_order_line_id'] ?? 0] ?? throw new RuntimeException("Line {$n}: that line is not on {$order->number}.");
            $quantity = round((float) ($row['quantity'] ?? 0), 3);
            $price = (float) ($row['unit_price'] ?? -1);

            if ($quantity <= 0) {
                throw new RuntimeException("Line {$n}: the quantity invoiced must be greater than zero.");
            }

            if ($price < 0) {
                throw new RuntimeException("Line {$n}: enter the unit price on the supplier's invoice.");
            }

            $rate = isset($row['vat_rate']) && $row['vat_rate'] !== '' ? (float) $row['vat_rate'] : (float) $orderLine->vat_rate;
            $amount = Lines::money($quantity * $price);
            $lineVat = Lines::money($amount * $rate / 100);
            $orderPrice = (float) $orderLine->unit_price;
            $matchable = $orderLine->matchable();
            $quantityVariance = round($quantity - $matchable, 3);

            $priceOff = abs($price - $orderPrice) > max(0.005, $orderPrice * $priceTolerance / 100);
            $quantityOff = $quantityVariance > 0.0005 && $quantityVariance > max(0, $matchable) * $quantityTolerance / 100;

            $expense = null;
            if ($orderLine->isService()) {
                $expense = $row['expense_account_id'] ?? $orderLine->expense_account_id;
                if ($expense && ! Account::query()->whereKey($expense)->where('type', 'expense')->where('is_active', true)->exists()) {
                    throw new RuntimeException("Line {$n}: choose an active expense account.");
                }
            }

            $invoice->lines()->create([
                'purchase_order_line_id' => $orderLine->id,
                'line_type' => $orderLine->line_type,
                'description' => $orderLine->description,
                'quantity' => $quantity,
                'unit_price' => $price,
                'vat_rate' => $rate,
                'amount' => $amount,
                'vat_amount' => $lineVat,
                'order_unit_price' => $orderPrice,
                'matchable_quantity' => $matchable,
                'price_variance' => Lines::money(($price - $orderPrice) * $quantity),
                'quantity_variance' => $quantityVariance,
                'flagged' => $priceOff || $quantityOff,
                'expense_account_id' => $expense,
            ]);

            $subtotal += $amount;
            $vat += $lineVat;
            $flagged = $flagged || $priceOff || $quantityOff;
        }

        $invoice->update([
            'subtotal' => Lines::money($subtotal),
            'vat_amount' => Lines::money($vat),
            'total' => Lines::money($subtotal + $vat),
            'match_status' => $flagged ? SupplierInvoice::VARIANCE : SupplierInvoice::MATCHED,
            'status' => $flagged ? SupplierInvoice::STATUS_AWAITING_APPROVAL : SupplierInvoice::STATUS_DRAFT,
        ]);
    }

    private function invoiceableOrder(int $id): PurchaseOrder
    {
        $order = PurchaseOrder::query()->findOrFail($id);

        if (in_array($order->status, [PurchaseOrder::STATUS_DRAFT, PurchaseOrder::STATUS_SUBMITTED, PurchaseOrder::STATUS_CANCELLED], true)) {
            throw new RuntimeException("Purchase order {$order->number} is {$order->status}; invoices are matched against approved orders only.");
        }

        return $order;
    }

    /** @return array<string, mixed> */
    private function header(array $data, PurchaseOrder $order): array
    {
        $date = $data['invoice_date'] ?? now()->toDateString();
        $terms = (int) ($order->supplier?->payment_terms_days ?? 0);

        return [
            'supplier_invoice_number' => trim($data['supplier_invoice_number']),
            'invoice_date' => $date,
            'due_date' => $data['due_date'] ?? now()->parse($date)->addDays($terms)->toDateString(),
            'notes' => $data['notes'] ?? null,
        ];
    }

    private function assertNewNumber(int $supplierId, string $number): void
    {
        $existing = SupplierInvoice::query()->where('supplier_id', $supplierId)->where('supplier_invoice_number', trim($number))->first();

        if ($existing) {
            throw new RuntimeException("This supplier's invoice {$number} has already been entered as {$existing->number}.");
        }
    }

    /** The database refuses a duplicate number again if two people enter it at once. */
    private function guardDuplicate(callable $work, array $data): SupplierInvoice
    {
        try {
            return $work();
        } catch (UniqueConstraintViolationException) {
            throw new RuntimeException("This supplier's invoice {$data['supplier_invoice_number']} has already been entered.");
        }
    }

    private function lock(SupplierInvoice $invoice): SupplierInvoice
    {
        return SupplierInvoice::query()->whereKey($invoice->id)->lockForUpdate()->firstOrFail();
    }

    /** @param  list<string>  $allowed */
    private function assertStatus(SupplierInvoice $invoice, array $allowed, string $verb): void
    {
        if (! in_array($invoice->status, $allowed, true)) {
            throw new RuntimeException("{$invoice->number} is {$invoice->status} and cannot be {$verb}.");
        }
    }
}
