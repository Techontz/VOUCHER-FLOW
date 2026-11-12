<?php

namespace App\Services\Erp\Sales;

use App\Models\Erp\Customer;
use App\Models\Erp\Sales\LoadingOrder;
use App\Models\Erp\Sales\SalesInvoice;
use App\Models\Erp\Sales\SalesOrder;
use App\Models\Erp\Sales\SalesQuotation;
use App\Models\Erp\Sales\SalesReceiptAllocation;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Quotations and sales orders, from draft to approval, and the order's
 * status as payment, loading and delivery happen to it.
 *
 * Every state change locks the row and re-checks the state it expects, so
 * two people pressing the same button get one result and one refusal.
 */
class SalesOrders
{
    public function __construct(
        private readonly SalesPricing $pricing,
        private readonly CreditPolicy $policy,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
    ) {}

    /* ───────────────────────────────────────────────────── quotations ── */

    /**
     * @param  array<string, mixed>  $header
     * @param  list<array<string, mixed>>  $lines
     */
    public function saveQuotation(?SalesQuotation $quotation, array $header, array $lines, User $actor): SalesQuotation
    {
        return DB::transaction(function () use ($quotation, $header, $lines, $actor) {
            $customer = $this->activeCustomer((int) $header['customer_id']);
            $date = $header['quote_date'] ?? now()->toDateString();
            $priced = $this->pricing->priceLines($customer, $lines, $date);
            $fields = [
                'customer_id' => $customer->id,
                'quote_date' => $date,
                'valid_until' => $header['valid_until'] ?? now()->parse($date)->addDays(14)->toDateString(),
                'notes' => $header['notes'] ?? null,
                ...SalesPricing::totals($priced),
            ];

            if ($quotation) {
                $quotation = $this->lockQuotation($quotation);
                $this->expect($quotation->status, ['draft'], $quotation->number, 'edited');
                $quotation->update($fields);
                $quotation->lines()->delete();
                $verb = 'updated';
            } else {
                $quotation = SalesQuotation::create([
                    ...$fields,
                    'number' => $this->numbers->next('QUO'),
                    'status' => 'draft',
                    'created_by' => $actor->id,
                ]);
                $verb = 'created';
            }

            foreach ($priced as $line) {
                $quotation->lines()->create($line);
            }

            $this->audit->log("sales.quotation.{$verb}", ucfirst($verb)." quotation {$quotation->number} for {$customer->name}", $quotation, actor: $actor);

            return $quotation->load('lines.product.unit', 'customer');
        });
    }

    public function setQuotationStatus(SalesQuotation $quotation, string $status, User $actor): SalesQuotation
    {
        $allowed = ['sent' => ['draft'], 'rejected' => ['draft', 'sent'], 'cancelled' => ['draft', 'sent']];

        return DB::transaction(function () use ($quotation, $status, $allowed, $actor) {
            $locked = $this->lockQuotation($quotation);
            $this->expect($locked->status, $allowed[$status], $locked->number, $status === 'sent' ? 'sent' : $status);
            $locked->update(['status' => $status]);
            $this->audit->log("sales.quotation.{$status}", "Quotation {$locked->number} {$status}", $locked, actor: $actor);

            return $locked;
        });
    }

    /** An accepted quotation becomes a draft order with the same lines and prices. */
    public function convert(SalesQuotation $quotation, User $actor): SalesOrder
    {
        return DB::transaction(function () use ($quotation, $actor) {
            $locked = $this->lockQuotation($quotation);
            $this->expect($locked->status, ['draft', 'sent'], $locked->number, 'converted');

            if ($locked->valid_until && $locked->valid_until->lt(now()->startOfDay())) {
                throw new RuntimeException("{$locked->number} expired on {$locked->valid_until->toDateString()}. Prepare a new quotation at today's prices.");
            }

            $order = $this->saveOrder(null, [
                'customer_id' => $locked->customer_id,
                'quotation_id' => $locked->id,
                'notes' => $locked->notes,
            ], $locked->lines->map(fn ($l) => [
                'product_id' => $l->product_id, 'description' => $l->description, 'quantity' => (float) $l->quantity,
                'unit_price' => (float) $l->unit_price, 'discount_percent' => (float) $l->discount_percent, 'tax_rate' => (float) $l->tax_rate,
            ])->all(), $actor);

            $locked->update(['status' => 'converted', 'sales_order_id' => $order->id]);
            $this->audit->log('sales.quotation.converted', "Converted {$locked->number} into order {$order->number}", $locked, actor: $actor);

            return $order;
        });
    }

    /* ───────────────────────────────────────────────────────── orders ── */

    /**
     * @param  array<string, mixed>  $header
     * @param  list<array<string, mixed>>  $lines  quantity is the quantity ordered
     */
    public function saveOrder(?SalesOrder $order, array $header, array $lines, User $actor): SalesOrder
    {
        return DB::transaction(function () use ($order, $header, $lines, $actor) {
            $customer = $this->activeCustomer((int) $header['customer_id']);
            $date = $header['order_date'] ?? now()->toDateString();
            $priced = $this->pricing->priceLines($customer, $lines, $date);
            $fields = [
                'customer_id' => $customer->id,
                'order_date' => $date,
                'required_date' => $header['required_date'] ?? null,
                'warehouse_id' => $header['warehouse_id'] ?? null,
                'delivery_address' => $header['delivery_address'] ?? $customer->address,
                'notes' => $header['notes'] ?? null,
                ...SalesPricing::totals($priced),
            ];

            if ($order) {
                $order = $this->lock($order);
                $this->expect($order->status, [SalesOrder::STATUS_DRAFT], $order->number, 'edited');
                $order->update($fields);
                $order->lines()->delete();
                $verb = 'updated';
            } else {
                $order = SalesOrder::create([
                    ...$fields,
                    'quotation_id' => $header['quotation_id'] ?? null,
                    'number' => $this->numbers->next('SO'),
                    'status' => SalesOrder::STATUS_DRAFT,
                    'created_by' => $actor->id,
                ]);
                $verb = 'created';
            }

            foreach ($priced as $line) {
                $quantity = $line['quantity'];
                unset($line['quantity']);
                $order->lines()->create([...$line, 'quantity_ordered' => $quantity]);
            }

            $this->audit->log("sales.order.{$verb}", ucfirst($verb)." order {$order->number} for {$customer->name}", $order, actor: $actor);

            return $order->load('lines.product.unit', 'customer');
        });
    }

    public function submit(SalesOrder $order, User $actor): SalesOrder
    {
        return DB::transaction(function () use ($order, $actor) {
            $locked = $this->lock($order);
            $this->expect($locked->status, [SalesOrder::STATUS_DRAFT], $locked->number, 'submitted');

            if ($locked->lines()->count() === 0) {
                throw new RuntimeException("{$locked->number} has no lines.");
            }

            $locked->update(['status' => SalesOrder::STATUS_SUBMITTED, 'submitted_by' => $actor->id, 'submitted_at' => now()]);
            $this->audit->log('sales.order.submitted', "Submitted {$locked->number} for approval", $locked, actor: $actor);

            return $locked;
        });
    }

    /** What the credit policy would say if the order were approved now. */
    public function policyPreview(SalesOrder $order): array
    {
        return $this->policy->evaluate($order->customer, (float) $order->total, $order->id);
    }

    /**
     * Approves the order, at the quantities given or as ordered, under the
     * customer policy. A refusal can be overridden only with a written reason,
     * which stays on the order and in the audit trail.
     *
     * @param  array<int, float>  $approved  order line id => quantity approved
     */
    public function approve(SalesOrder $order, User $actor, array $approved = [], ?string $overrideReason = null): SalesOrder
    {
        return DB::transaction(function () use ($order, $actor, $approved, $overrideReason) {
            $locked = $this->lock($order);
            $this->expect($locked->status, [SalesOrder::STATUS_SUBMITTED], $locked->number, 'approved');

            $lines = $locked->lines()->get();
            $any = false;

            foreach ($lines as $line) {
                $quantity = array_key_exists($line->id, $approved) ? (float) $approved[$line->id] : (float) $line->quantity_ordered;

                if ($quantity < 0 || $quantity > (float) $line->quantity_ordered + 0.0005) {
                    throw new RuntimeException('An approved quantity must be between zero and the quantity ordered.');
                }

                $any = $any || $quantity > 0;
                $line->fill([
                    'quantity_approved' => $quantity,
                    ...SalesPricing::amounts($quantity, (float) $line->unit_price, (float) $line->discount_percent, (float) $line->tax_rate),
                ])->save();
            }

            if (! $any) {
                throw new RuntimeException('Approve at least one line, or reject the order instead.');
            }

            $totals = SalesPricing::totals($lines);
            $customer = Customer::query()->withTrashed()->findOrFail($locked->customer_id);
            $check = $this->policy->evaluate($customer, $totals['total'], $locked->id);
            $override = trim((string) $overrideReason);

            if (! $check['passed'] && $override === '') {
                throw new RuntimeException(implode(' ', $check['reasons']).' The order cannot be approved unless someone with approval rights overrides the credit policy with a reason.');
            }

            $prepayment = $check['mode'] === SalesOrder::MODE_PREPAYMENT;

            $locked->update([
                ...$totals,
                'status' => $prepayment ? SalesOrder::STATUS_AWAITING_PAYMENT : SalesOrder::STATUS_READY,
                'payment_mode' => $check['mode'],
                'policy_check' => $check,
                'override_reason' => ! $check['passed'] ? mb_substr($override, 0, 500) : null,
                'overridden_by' => ! $check['passed'] ? $actor->id : null,
                'approved_by' => $actor->id,
                'approved_at' => now(),
            ]);

            $this->audit->log('sales.order.approved', "Approved {$locked->number}".($prepayment ? ', waiting for payment verification' : ' on credit'), $locked, actor: $actor);

            if (! $check['passed']) {
                $this->audit->log('sales.order.credit_override', "Overrode the credit policy on {$locked->number}: {$override}", $locked, actor: $actor);
            }

            // A payment verified before approval (rare, but possible) counts at once.
            return $this->refreshPayment($locked, $actor);
        });
    }

    public function reject(SalesOrder $order, string $reason, User $actor): SalesOrder
    {
        return DB::transaction(function () use ($order, $reason, $actor) {
            $locked = $this->lock($order);
            $this->expect($locked->status, [SalesOrder::STATUS_SUBMITTED], $locked->number, 'rejected');
            $locked->update(['status' => SalesOrder::STATUS_REJECTED, 'rejection_reason' => mb_substr($reason, 0, 500)]);
            $this->audit->log('sales.order.rejected', "Rejected {$locked->number}: {$reason}", $locked, actor: $actor);

            return $locked;
        });
    }

    public function cancel(SalesOrder $order, User $actor): SalesOrder
    {
        return DB::transaction(function () use ($order, $actor) {
            $locked = $this->lock($order);
            $this->expect($locked->status, [SalesOrder::STATUS_DRAFT, SalesOrder::STATUS_SUBMITTED, SalesOrder::STATUS_AWAITING_PAYMENT, SalesOrder::STATUS_READY], $locked->number, 'cancelled');

            if (LoadingOrder::query()->where('sales_order_id', $locked->id)->where('status', '!=', LoadingOrder::STATUS_CANCELLED)->exists()) {
                throw new RuntimeException("{$locked->number} already has goods loaded or being loaded and cannot be cancelled.");
            }

            if (SalesInvoice::query()->where('sales_order_id', $locked->id)->where('status', SalesInvoice::STATUS_POSTED)->exists()) {
                throw new RuntimeException("{$locked->number} has a posted invoice. Raise a credit note against it first.");
            }

            SalesInvoice::query()->where('sales_order_id', $locked->id)->where('status', SalesInvoice::STATUS_DRAFT)
                ->update(['status' => SalesInvoice::STATUS_CANCELLED]);
            $locked->lines()->update(['quantity_invoiced' => 0]);
            $locked->update(['status' => SalesOrder::STATUS_CANCELLED]);
            $this->audit->log('sales.order.cancelled', "Cancelled {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    /* ─────────────────────────────────────────── payment & fulfilment ── */

    /** Verified money applied to this order's invoices. */
    public function verifiedPayments(SalesOrder $order): float
    {
        return round((float) SalesReceiptAllocation::query()
            ->whereHas('receipt', fn ($q) => $q->where('status', 'verified'))
            ->whereHas('invoice', fn ($q) => $q->where('sales_order_id', $order->id)->where('status', SalesInvoice::STATUS_POSTED))
            ->sum('amount'), 2);
    }

    /** A prepayment order is released for loading once verified payments cover it. */
    public function refreshPayment(SalesOrder $order, ?User $actor = null): SalesOrder
    {
        if ($order->status !== SalesOrder::STATUS_AWAITING_PAYMENT) {
            return $order;
        }

        $paid = $this->verifiedPayments($order);

        if ($paid + 0.004 >= (float) $order->total) {
            $order->update(['status' => SalesOrder::STATUS_READY, 'payment_verified_at' => now()]);
            $this->audit->log('sales.order.payment_verified', "Payment for {$order->number} verified; released for loading", $order, actor: $actor);
        }

        return $order;
    }

    /**
     * Re-derives loaded and received totals on the order lines from the
     * loading orders, and the order's status from where its goods are.
     */
    public function refreshFulfilment(SalesOrder $order): SalesOrder
    {
        $loadings = LoadingOrder::query()->where('sales_order_id', $order->id)
            ->where('status', '!=', LoadingOrder::STATUS_CANCELLED)->with('lines')->get();

        foreach ($order->lines()->get() as $line) {
            $loaded = 0.0;
            $received = 0.0;
            foreach ($loadings as $lo) {
                foreach ($lo->lines->where('sales_order_line_id', $line->id) as $l) {
                    if ($lo->status !== LoadingOrder::STATUS_OPEN) {
                        $loaded += (float) $l->quantity_loaded;
                    }
                    if ($lo->status === LoadingOrder::STATUS_DELIVERED) {
                        $received += (float) $l->quantity_received;
                    }
                }
            }
            $line->update(['quantity_loaded' => $loaded, 'quantity_received' => $received]);
        }

        if (! in_array($order->status, [SalesOrder::STATUS_READY, SalesOrder::STATUS_LOADING, SalesOrder::STATUS_DISPATCHED, SalesOrder::STATUS_DELIVERED], true)) {
            return $order;
        }

        $remaining = array_sum($this->remainingToLoad($order));
        $status = match (true) {
            $loadings->contains(fn ($lo) => in_array($lo->status, [LoadingOrder::STATUS_OPEN, LoadingOrder::STATUS_LOADED], true)) => SalesOrder::STATUS_LOADING,
            $remaining > 0.0005 => SalesOrder::STATUS_READY,
            $loadings->isNotEmpty() && $loadings->every(fn ($lo) => $lo->status === LoadingOrder::STATUS_DELIVERED) => SalesOrder::STATUS_DELIVERED,
            $loadings->isNotEmpty() => SalesOrder::STATUS_DISPATCHED,
            default => SalesOrder::STATUS_READY,
        };

        if ($status !== $order->status) {
            $order->update(['status' => $status]);
        }

        return $order;
    }

    /**
     * Per order line, what may still go on a truck: approved, less what open
     * loading orders hold, less what confirmed loadings actually took.
     *
     * @return array<int, float>
     */
    public function remainingToLoad(SalesOrder $order): array
    {
        $loadings = LoadingOrder::query()->where('sales_order_id', $order->id)
            ->where('status', '!=', LoadingOrder::STATUS_CANCELLED)->with('lines')->get();
        $out = [];

        foreach ($order->lines()->get() as $line) {
            $held = 0.0;
            foreach ($loadings as $lo) {
                foreach ($lo->lines->where('sales_order_line_id', $line->id) as $l) {
                    $held += $lo->status === LoadingOrder::STATUS_OPEN ? (float) $l->quantity_approved : (float) $l->quantity_loaded;
                }
            }
            $out[$line->id] = max(0, round((float) $line->quantity_approved - $held, 3));
        }

        return $out;
    }

    /* ───────────────────────────────────────────────────────── helpers ── */

    public function activeCustomer(int $id): Customer
    {
        $customer = Customer::query()->find($id) ?? throw new RuntimeException('That customer is not in this company.');

        if (! $customer->is_active) {
            throw new RuntimeException("{$customer->name} is inactive.");
        }

        return $customer;
    }

    public function lock(SalesOrder $order): SalesOrder
    {
        return SalesOrder::query()->whereKey($order->id)->lockForUpdate()->firstOrFail();
    }

    private function lockQuotation(SalesQuotation $quotation): SalesQuotation
    {
        return SalesQuotation::query()->whereKey($quotation->id)->lockForUpdate()->firstOrFail();
    }

    /** @param  list<string>  $allowed */
    public static function expect(string $status, array $allowed, string $number, string $verb): void
    {
        if (! in_array($status, $allowed, true)) {
            throw new RuntimeException("{$number} is ".str_replace('_', ' ', $status)." and cannot be {$verb}.");
        }
    }
}
