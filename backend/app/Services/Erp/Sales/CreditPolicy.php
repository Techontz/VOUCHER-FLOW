<?php

namespace App\Services\Erp\Sales;

use App\Models\Erp\Customer;
use App\Models\Erp\Sales\SalesInvoice;
use App\Models\Erp\Sales\SalesOrder;
use Illuminate\Support\Facades\DB;

/**
 * The customer policy applied when an order is approved (spec §6).
 *
 * A prepayment customer always passes, but the order then waits for a
 * verified payment before anything is loaded. A credit customer passes only
 * when what they already owe, plus approved orders not yet invoiced, plus
 * this order stays within their credit limit, and no invoice of theirs is
 * past its due date.
 */
class CreditPolicy
{
    /**
     * @return array{mode: string, passed: bool, credit_limit: float, outstanding: float, uninvoiced_orders: float,
     *     this_order: float, exposure: float, overdue_invoices: int, oldest_overdue_days: int, reasons: list<string>, checked_at: string}
     */
    public function evaluate(Customer $customer, float $orderTotal, ?int $excludeOrderId = null): array
    {
        $outstanding = $this->outstanding($customer->id);
        $uninvoiced = $this->uninvoicedOrders($customer->id, $excludeOrderId);
        $overdue = SalesInvoice::query()
            ->where('customer_id', $customer->id)
            ->where('status', SalesInvoice::STATUS_POSTED)
            ->whereDate('due_date', '<', now()->toDateString())
            ->whereRaw('total - amount_paid - amount_credited > 0.004')
            ->orderBy('due_date')
            ->get(['id', 'due_date']);

        $limit = (float) $customer->credit_limit;
        $exposure = round($outstanding + $uninvoiced + $orderTotal, 2);
        $prepayment = (bool) $customer->requires_prepayment;
        $reasons = [];

        if (! $prepayment) {
            if ($exposure > $limit + 0.004) {
                $reasons[] = sprintf(
                    '%s would owe TZS %s against a credit limit of TZS %s (TZS %s outstanding, TZS %s on approved orders not yet invoiced, TZS %s on this order).',
                    $customer->name, number_format($exposure, 2), number_format($limit, 2),
                    number_format($outstanding, 2), number_format($uninvoiced, 2), number_format($orderTotal, 2),
                );
            }

            if ($overdue->isNotEmpty()) {
                $days = (int) $overdue->first()->due_date->diffInDays(now()->startOfDay());
                $reasons[] = sprintf(
                    '%s has %d invoice%s past the %d-day payment terms, the oldest %d day%s overdue.',
                    $customer->name, $overdue->count(), $overdue->count() === 1 ? '' : 's',
                    $customer->payment_terms_days, $days, $days === 1 ? '' : 's',
                );
            }
        }

        return [
            'mode' => $prepayment ? SalesOrder::MODE_PREPAYMENT : SalesOrder::MODE_CREDIT,
            'passed' => $reasons === [],
            'credit_limit' => $limit,
            'outstanding' => $outstanding,
            'uninvoiced_orders' => $uninvoiced,
            'this_order' => round($orderTotal, 2),
            'exposure' => $exposure,
            'overdue_invoices' => $overdue->count(),
            'oldest_overdue_days' => $overdue->isNotEmpty() ? (int) $overdue->first()->due_date->diffInDays(now()->startOfDay()) : 0,
            'reasons' => $reasons,
            'checked_at' => now()->toIso8601String(),
        ];
    }

    public function outstanding(int $customerId): float
    {
        return round((float) SalesInvoice::query()
            ->where('customer_id', $customerId)
            ->where('status', SalesInvoice::STATUS_POSTED)
            ->sum(DB::raw('total - amount_paid - amount_credited')), 2);
    }

    /** Approved, unfinished orders' value not yet covered by an invoice (draft or posted). */
    private function uninvoicedOrders(int $customerId, ?int $excludeOrderId): float
    {
        $orders = SalesOrder::query()
            ->where('customer_id', $customerId)
            ->whereIn('status', SalesOrder::OPEN)
            ->when($excludeOrderId, fn ($q) => $q->whereKeyNot($excludeOrderId))
            ->withSum(['invoices as invoiced' => fn ($q) => $q->where('status', '!=', SalesInvoice::STATUS_CANCELLED)], 'total')
            ->get(['id', 'total']);

        return round($orders->sum(fn ($o) => max(0, (float) $o->total - (float) $o->invoiced)), 2);
    }
}
