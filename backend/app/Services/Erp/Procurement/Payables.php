<?php

namespace App\Services\Erp\Procurement;

use App\Models\Erp\Procurement\PurchaseOrder;
use App\Models\Erp\Procurement\PurchaseRequisition;
use App\Models\Erp\Procurement\SupplierInvoice;
use App\Models\Erp\Procurement\SupplierPayment;
use App\Models\Erp\Supplier;
use Illuminate\Support\Carbon;

/**
 * What the company owes its suppliers, read from posted invoices and posted
 * payments: the overview figures, the ageing and a supplier's statement.
 */
class Payables
{
    public const BUCKETS = ['current', 'days_1_30', 'days_31_60', 'days_61_90', 'over_90'];

    /** @return array<string, mixed> */
    public function overview(): array
    {
        $open = SupplierInvoice::query()->where('status', SupplierInvoice::STATUS_POSTED)->whereColumn('amount_paid', '<', 'total');
        $today = now()->toDateString();

        return [
            'open_requisitions' => PurchaseRequisition::query()->whereIn('status', [PurchaseRequisition::STATUS_DRAFT, PurchaseRequisition::STATUS_SUBMITTED, PurchaseRequisition::STATUS_APPROVED])->count(),
            'requisitions_awaiting_approval' => PurchaseRequisition::query()->where('status', PurchaseRequisition::STATUS_SUBMITTED)->count(),
            'orders_awaiting_approval' => PurchaseOrder::query()->where('status', PurchaseOrder::STATUS_SUBMITTED)->count(),
            'orders_to_receive' => PurchaseOrder::query()->whereIn('status', PurchaseOrder::RECEIVABLE)->count(),
            'invoices_to_match' => SupplierInvoice::query()->whereIn('status', [SupplierInvoice::STATUS_DRAFT, SupplierInvoice::STATUS_AWAITING_APPROVAL, SupplierInvoice::STATUS_APPROVED])->count(),
            'invoices_with_variance' => SupplierInvoice::query()->where('status', SupplierInvoice::STATUS_AWAITING_APPROVAL)->count(),
            'payables_outstanding' => round((float) (clone $open)->selectRaw('COALESCE(SUM(total - amount_paid), 0) as v')->value('v'), 2),
            'payables_overdue' => round((float) (clone $open)->where('due_date', '<', $today)->selectRaw('COALESCE(SUM(total - amount_paid), 0) as v')->value('v'), 2),
            'payables_due_7_days' => round((float) (clone $open)->whereBetween('due_date', [$today, now()->addDays(7)->toDateString()])->selectRaw('COALESCE(SUM(total - amount_paid), 0) as v')->value('v'), 2),
            'ordered_this_month' => round((float) PurchaseOrder::query()->whereNotIn('status', [PurchaseOrder::STATUS_DRAFT, PurchaseOrder::STATUS_CANCELLED])->where('order_date', '>=', now()->startOfMonth()->toDateString())->sum('total'), 2),
            'recent_orders' => PurchaseOrder::query()->with('supplier:id,name')->latest('id')->limit(6)->get(['id', 'number', 'supplier_id', 'status', 'total', 'order_date', 'expected_date']),
        ];
    }

    /** @return array<string, mixed> */
    public function ageing(?string $asOf = null): array
    {
        $asOf = Carbon::parse($asOf ?? now()->toDateString())->startOfDay();
        $rows = [];
        $totals = array_fill_keys([...self::BUCKETS, 'total'], 0.0);

        $invoices = SupplierInvoice::query()
            ->with('supplier:id,code,name')
            ->where('status', SupplierInvoice::STATUS_POSTED)
            ->whereColumn('amount_paid', '<', 'total')
            ->where('invoice_date', '<=', $asOf->toDateString())
            ->orderBy('due_date')
            ->get();

        foreach ($invoices as $invoice) {
            $outstanding = $invoice->outstanding;
            $late = (int) $invoice->due_date->startOfDay()->diffInDays($asOf, false);
            $bucket = $late <= 0 ? 'current' : ($late <= 30 ? 'days_1_30' : ($late <= 60 ? 'days_31_60' : ($late <= 90 ? 'days_61_90' : 'over_90')));

            $rows[$invoice->supplier_id] ??= [
                'supplier' => $invoice->supplier?->only(['id', 'code', 'name']),
                ...array_fill_keys([...self::BUCKETS, 'total'], 0.0),
                'invoices' => [],
            ];
            $rows[$invoice->supplier_id][$bucket] = round($rows[$invoice->supplier_id][$bucket] + $outstanding, 2);
            $rows[$invoice->supplier_id]['total'] = round($rows[$invoice->supplier_id]['total'] + $outstanding, 2);
            $rows[$invoice->supplier_id]['invoices'][] = [
                'id' => $invoice->id, 'number' => $invoice->number, 'supplier_invoice_number' => $invoice->supplier_invoice_number,
                'invoice_date' => $invoice->invoice_date->toDateString(), 'due_date' => $invoice->due_date->toDateString(),
                'days_overdue' => max(0, $late), 'bucket' => $bucket, 'outstanding' => $outstanding,
            ];
            $totals[$bucket] = round($totals[$bucket] + $outstanding, 2);
            $totals['total'] = round($totals['total'] + $outstanding, 2);
        }

        usort($rows, fn ($a, $b) => $b['total'] <=> $a['total']);

        return ['as_of' => $asOf->toDateString(), 'buckets' => self::BUCKETS, 'rows' => array_values($rows), 'totals' => $totals];
    }

    /**
     * Invoices raise what is owed, payments reduce it; a running balance from
     * the opening position at `from`.
     *
     * @return array<string, mixed>
     */
    public function statement(Supplier $supplier, ?string $from = null, ?string $to = null): array
    {
        $from = $from ?? now()->subDays(90)->toDateString();
        $to = $to ?? now()->toDateString();

        $invoices = SupplierInvoice::query()->where('supplier_id', $supplier->id)->where('status', SupplierInvoice::STATUS_POSTED);
        $payments = SupplierPayment::query()->where('supplier_id', $supplier->id)->where('status', SupplierPayment::STATUS_POSTED);

        $opening = round((float) (clone $invoices)->where('invoice_date', '<', $from)->sum('total')
            - (float) (clone $payments)->where('payment_date', '<', $from)->sum('amount'), 2);

        $entries = collect()
            ->merge((clone $invoices)->whereBetween('invoice_date', [$from, $to])->get()->map(fn ($i) => [
                'date' => $i->invoice_date->toDateString(), 'type' => 'invoice', 'id' => $i->id, 'number' => $i->number,
                'reference' => $i->supplier_invoice_number, 'due_date' => $i->due_date->toDateString(),
                'debit' => 0.0, 'credit' => (float) $i->total, 'sort' => $i->posted_at?->timestamp ?? 0,
            ]))
            ->merge((clone $payments)->whereBetween('payment_date', [$from, $to])->get()->map(fn ($p) => [
                'date' => $p->payment_date->toDateString(), 'type' => 'payment', 'id' => $p->id, 'number' => $p->number,
                'reference' => $p->reference, 'due_date' => null,
                'debit' => (float) $p->amount, 'credit' => 0.0, 'sort' => $p->posted_at?->timestamp ?? 0,
            ]))
            ->sortBy([['date', 'asc'], ['sort', 'asc']])
            ->values();

        $balance = $opening;
        $lines = $entries->map(function ($e) use (&$balance) {
            $balance = round($balance + $e['credit'] - $e['debit'], 2);
            unset($e['sort']);

            return [...$e, 'balance' => $balance];
        });

        return [
            'supplier' => $supplier->only(['id', 'code', 'name', 'phone', 'email', 'address', 'city', 'payment_terms_days']),
            'from' => $from,
            'to' => $to,
            'opening_balance' => $opening,
            'entries' => $lines->values(),
            'total_invoiced' => round($entries->sum('credit'), 2),
            'total_paid' => round($entries->sum('debit'), 2),
            'closing_balance' => $balance,
        ];
    }
}
