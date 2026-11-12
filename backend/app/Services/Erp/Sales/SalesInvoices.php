<?php

namespace App\Services\Erp\Sales;

use App\Models\Erp\Customer;
use App\Models\Erp\Sales\LoadingOrder;
use App\Models\Erp\Sales\SalesInvoice;
use App\Models\Erp\Sales\SalesOrder;
use App\Models\Erp\Sales\SalesOrderLine;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Invoices raised from an order: for what was approved (the usual way to ask
 * a prepayment customer for money) or for what one loading order delivered.
 * Each order line remembers how much has been invoiced, so nothing is billed
 * twice. Posting is once, under lock:
 *
 *   Dr Accounts receivable (total)   Cr Sales revenue (net of discount)   Cr VAT payable (VAT)
 */
class SalesInvoices
{
    public function __construct(
        private readonly SalesOrders $orders,
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    public function fromOrder(SalesOrder $order, User $actor, ?LoadingOrder $delivery = null, ?string $date = null): SalesInvoice
    {
        return DB::transaction(function () use ($order, $actor, $delivery, $date) {
            $locked = $this->orders->lock($order);
            SalesOrders::expect($locked->status, [...SalesOrder::OPEN, SalesOrder::STATUS_DELIVERED], $locked->number, 'invoiced');

            $lines = SalesOrderLine::query()->where('sales_order_id', $locked->id)->lockForUpdate()->get()->keyBy('id');
            $wanted = [];

            if ($delivery) {
                if ($delivery->sales_order_id !== $locked->id || $delivery->status !== LoadingOrder::STATUS_DELIVERED) {
                    throw new RuntimeException("{$delivery->number} has not been delivered on {$locked->number}; invoice what was delivered once proof of delivery is recorded.");
                }

                if (SalesInvoice::query()->where('loading_order_id', $delivery->id)->where('status', '!=', SalesInvoice::STATUS_CANCELLED)->exists()) {
                    throw new RuntimeException("The delivery on {$delivery->number} has already been invoiced.");
                }

                foreach ($delivery->lines as $l) {
                    $wanted[$l->sales_order_line_id] = ($wanted[$l->sales_order_line_id] ?? 0) + (float) $l->quantity_received;
                }
            } else {
                foreach ($lines as $line) {
                    $wanted[$line->id] = (float) $line->quantity_approved;
                }
            }

            $invoiceLines = [];
            foreach ($wanted as $lineId => $quantity) {
                $line = $lines[$lineId];
                $open = round((float) $line->quantity_approved - (float) $line->quantity_invoiced, 3);
                $quantity = min($quantity, $open);

                if ($quantity <= 0.0005) {
                    continue;
                }

                $invoiceLines[] = [
                    'sales_order_line_id' => $line->id,
                    'product_id' => $line->product_id,
                    'description' => $line->description,
                    'quantity' => $quantity,
                    ...SalesPricing::amounts($quantity, (float) $line->unit_price, (float) $line->discount_percent, (float) $line->tax_rate),
                ];
                $line->update(['quantity_invoiced' => (float) $line->quantity_invoiced + $quantity]);
            }

            if (! $invoiceLines) {
                throw new RuntimeException("Everything approved on {$locked->number} has already been invoiced.");
            }

            $customer = Customer::query()->withTrashed()->findOrFail($locked->customer_id);
            $date ??= now()->toDateString();
            $invoice = SalesInvoice::create([
                'number' => $this->numbers->next('INV'),
                'customer_id' => $customer->id,
                'sales_order_id' => $locked->id,
                'loading_order_id' => $delivery?->id,
                'invoice_date' => $date,
                'due_date' => now()->parse($date)->addDays((int) $customer->payment_terms_days)->toDateString(),
                'status' => SalesInvoice::STATUS_DRAFT,
                ...SalesPricing::totals($invoiceLines),
                'created_by' => $actor->id,
            ]);

            foreach ($invoiceLines as $line) {
                $invoice->lines()->create($line);
            }

            $this->audit->log('sales.invoice.created', "Prepared invoice {$invoice->number} for {$locked->number}", $invoice, actor: $actor);

            return $invoice->load('lines.product.unit', 'customer');
        });
    }

    public function post(SalesInvoice $invoice, User $actor): SalesInvoice
    {
        return DB::transaction(function () use ($invoice, $actor) {
            $locked = SalesInvoice::query()->whereKey($invoice->id)->lockForUpdate()->firstOrFail();
            SalesOrders::expect($locked->status, [SalesInvoice::STATUS_DRAFT], $locked->number, 'posted');

            if ((float) $locked->total <= 0) {
                throw new RuntimeException("{$locked->number} has nothing to bill.");
            }

            $locked->update(['status' => SalesInvoice::STATUS_POSTED, 'posted_by' => $actor->id, 'posted_at' => now()]);

            if (BusinessConfig::of($this->tenant->company())->postsToLedger()) {
                $net = round((float) $locked->subtotal - (float) $locked->discount_total, 2);
                $lines = [
                    ['account' => 'receivable', 'debit' => (float) $locked->total, 'description' => $locked->number],
                    ['account' => 'sales', 'credit' => $net, 'description' => $locked->number],
                ];
                if ((float) $locked->tax_total > 0) {
                    $lines[] = ['account' => 'vat_output', 'credit' => (float) $locked->tax_total, 'description' => "VAT {$locked->number}"];
                }
                $this->journal->post($lines, "Sales invoice {$locked->number}", $locked->invoice_date->toDateString(), $locked, 'post', $actor);
            }

            $this->audit->log('sales.invoice.posted', "Posted invoice {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(['lines.product.unit', 'customer']);
        });
    }

    public function cancel(SalesInvoice $invoice, User $actor): SalesInvoice
    {
        return DB::transaction(function () use ($invoice, $actor) {
            $locked = SalesInvoice::query()->whereKey($invoice->id)->lockForUpdate()->firstOrFail();
            SalesOrders::expect($locked->status, [SalesInvoice::STATUS_DRAFT], $locked->number, 'cancelled');

            foreach ($locked->lines as $line) {
                if ($line->sales_order_line_id) {
                    SalesOrderLine::query()->whereKey($line->sales_order_line_id)->lockForUpdate()->first()
                        ?->decrement('quantity_invoiced', (float) $line->quantity);
                }
            }

            $locked->update(['status' => SalesInvoice::STATUS_CANCELLED]);
            $this->audit->log('sales.invoice.cancelled', "Cancelled draft invoice {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }
}
