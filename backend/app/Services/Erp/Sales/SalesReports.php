<?php

namespace App\Services\Erp\Sales;

use App\Models\Erp\Customer;
use App\Models\Erp\Sales\LoadingOrder;
use App\Models\Erp\Sales\SalesCreditNote;
use App\Models\Erp\Sales\SalesInvoice;
use App\Models\Erp\Sales\SalesOrder;
use App\Models\Erp\Sales\SalesQuotation;
use App\Models\Erp\Sales\SalesReceipt;
use App\Support\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Read-only figures built from the posted documents themselves, so a report
 * can never disagree with the invoices, receipts and credit notes behind it.
 */
class SalesReports
{
    public const BUCKETS = ['current', 'd1_30', 'd31_60', 'd61_90', 'd90_plus'];

    /** @return array<string, mixed> */
    public function overview(): array
    {
        $monthStart = now()->startOfMonth()->toDateString();
        $posted = SalesInvoice::query()->where('status', SalesInvoice::STATUS_POSTED);
        $pipeline = SalesOrder::query()->selectRaw('status, COUNT(*) as n, SUM(total) as value')->groupBy('status')->get()
            ->mapWithKeys(fn ($r) => [$r->status => ['count' => (int) $r->n, 'value' => round((float) $r->value, 2)]]);

        return [
            'sales_this_month' => round((float) (clone $posted)->whereDate('invoice_date', '>=', $monthStart)->sum(DB::raw('total - tax_total')), 2),
            'invoiced_this_month' => round((float) (clone $posted)->whereDate('invoice_date', '>=', $monthStart)->sum('total'), 2),
            'received_this_month' => round((float) SalesReceipt::query()->where('status', SalesReceipt::STATUS_VERIFIED)->whereDate('receipt_date', '>=', $monthStart)->sum('amount'), 2),
            'receivables' => round((float) (clone $posted)->sum(DB::raw('total - amount_paid - amount_credited')), 2),
            'overdue' => round((float) (clone $posted)->whereDate('due_date', '<', now()->toDateString())->whereRaw('total - amount_paid - amount_credited > 0.004')->sum(DB::raw('total - amount_paid - amount_credited')), 2),
            'open_quotations' => SalesQuotation::query()->whereIn('status', ['draft', 'sent'])->count(),
            'awaiting_verification' => SalesReceipt::query()->where('status', SalesReceipt::STATUS_RECORDED)->count(),
            'awaiting_payment' => SalesOrder::query()->where('status', SalesOrder::STATUS_AWAITING_PAYMENT)->count(),
            'open_discrepancies' => LoadingOrder::query()->where('discrepancy_status', 'open')->count(),
            'pipeline' => $pipeline,
            'recent_orders' => SalesOrder::query()->with('customer:id,name')->latest('id')->limit(8)
                ->get(['id', 'number', 'customer_id', 'order_date', 'status', 'total', 'payment_mode']),
        ];
    }

    /**
     * A customer's statement: the balance brought forward, then every posted
     * invoice, verified receipt and posted credit note in the period with a
     * running balance.
     *
     * @return array<string, mixed>
     */
    public function statement(Customer $customer, string $from, string $to): array
    {
        $rows = collect();

        SalesInvoice::query()->where('customer_id', $customer->id)->where('status', SalesInvoice::STATUS_POSTED)
            ->get(['id', 'number', 'invoice_date', 'due_date', 'total'])
            ->each(fn ($i) => $rows->push(['date' => $i->invoice_date->toDateString(), 'type' => 'invoice', 'id' => $i->id, 'number' => $i->number, 'detail' => 'Due '.$i->due_date->toDateString(), 'debit' => (float) $i->total, 'credit' => 0.0]));

        SalesReceipt::query()->where('customer_id', $customer->id)->where('status', SalesReceipt::STATUS_VERIFIED)
            ->get(['id', 'number', 'receipt_date', 'amount', 'method', 'reference'])
            ->each(fn ($r) => $rows->push(['date' => $r->receipt_date->toDateString(), 'type' => 'receipt', 'id' => $r->id, 'number' => $r->number, 'detail' => trim(str_replace('_', ' ', $r->method).' '.$r->reference), 'debit' => 0.0, 'credit' => (float) $r->amount]));

        SalesCreditNote::query()->where('customer_id', $customer->id)->where('status', SalesCreditNote::STATUS_POSTED)
            ->get(['id', 'number', 'credit_date', 'total', 'reason'])
            ->each(fn ($c) => $rows->push(['date' => $c->credit_date->toDateString(), 'type' => 'credit_note', 'id' => $c->id, 'number' => $c->number, 'detail' => $c->reason, 'debit' => 0.0, 'credit' => (float) $c->total]));

        $sorted = $rows->sortBy(fn ($r) => $r['date'].'|'.($r['type'] === 'invoice' ? 0 : 1).'|'.$r['number'])->values();
        $opening = round($sorted->filter(fn ($r) => $r['date'] < $from)->sum(fn ($r) => $r['debit'] - $r['credit']), 2);
        $balance = $opening;
        $lines = $sorted->filter(fn ($r) => $r['date'] >= $from && $r['date'] <= $to)->map(function ($r) use (&$balance) {
            $balance = round($balance + $r['debit'] - $r['credit'], 2);

            return [...$r, 'balance' => $balance];
        })->values();

        return [
            'customer' => $customer->only(['id', 'code', 'name', 'address', 'city', 'phone', 'email', 'tin', 'credit_limit', 'payment_terms_days', 'requires_prepayment', 'price_list']),
            'from' => $from,
            'to' => $to,
            'opening_balance' => $opening,
            'lines' => $lines,
            'total_debit' => round($lines->sum('debit'), 2),
            'total_credit' => round($lines->sum('credit'), 2),
            'closing_balance' => $balance,
            'aged' => $this->aged($to, $customer->id)['totals'],
        ];
    }

    /**
     * Aged receivables as at a date, by days past each invoice's due date.
     * Receipts and credit notes dated after the date are ignored, so an old
     * report can be reproduced.
     *
     * @return array{as_of: string, rows: list<array<string, mixed>>, totals: array<string, float>}
     */
    public function aged(string $asOf, ?int $customerId = null): array
    {
        $date = Carbon::parse($asOf)->startOfDay();
        $invoices = SalesInvoice::query()
            ->where('status', SalesInvoice::STATUS_POSTED)
            ->whereDate('invoice_date', '<=', $asOf)
            ->when($customerId, fn ($q) => $q->where('customer_id', $customerId))
            ->with('customer:id,code,name,payment_terms_days')
            ->withSum(['allocations as paid_by_date' => fn ($q) => $q->whereHas('receipt', fn ($r) => $r->where('status', SalesReceipt::STATUS_VERIFIED)->whereDate('receipt_date', '<=', $asOf))], 'amount')
            ->withSum(['creditNotes as credited_by_date' => fn ($q) => $q->where('status', SalesCreditNote::STATUS_POSTED)->whereDate('credit_date', '<=', $asOf)], 'total')
            ->get();

        $rows = [];
        $totals = array_fill_keys([...self::BUCKETS, 'total'], 0.0);

        foreach ($invoices as $invoice) {
            $open = round((float) $invoice->total - (float) $invoice->paid_by_date - (float) $invoice->credited_by_date, 2);

            if (abs($open) < 0.005) {
                continue;
            }

            $late = $invoice->due_date->lt($date) ? (int) $invoice->due_date->diffInDays($date) : 0;
            $bucket = match (true) {
                $late <= 0 => 'current',
                $late <= 30 => 'd1_30',
                $late <= 60 => 'd31_60',
                $late <= 90 => 'd61_90',
                default => 'd90_plus',
            };

            $key = $invoice->customer_id;
            $rows[$key] ??= [
                'customer_id' => $key, 'code' => $invoice->customer?->code, 'name' => $invoice->customer?->name,
                ...array_fill_keys([...self::BUCKETS, 'total'], 0.0), 'invoices' => [],
            ];
            $rows[$key][$bucket] = round($rows[$key][$bucket] + $open, 2);
            $rows[$key]['total'] = round($rows[$key]['total'] + $open, 2);
            $rows[$key]['invoices'][] = [
                'id' => $invoice->id, 'number' => $invoice->number, 'invoice_date' => $invoice->invoice_date->toDateString(),
                'due_date' => $invoice->due_date->toDateString(), 'days_overdue' => $late, 'bucket' => $bucket, 'open' => $open,
            ];
            $totals[$bucket] = round($totals[$bucket] + $open, 2);
            $totals['total'] = round($totals['total'] + $open, 2);
        }

        $rows = array_values($rows);
        usort($rows, fn ($a, $b) => $b['total'] <=> $a['total']);

        return ['as_of' => $date->toDateString(), 'rows' => $rows, 'totals' => $totals];
    }

    /**
     * Net sales (excluding VAT, after discounts and credit notes) grouped by
     * customer, product or month.
     *
     * @return array{group: string, rows: list<array<string, mixed>>, total: array<string, float>}
     */
    public function sales(string $group, string $from, string $to): array
    {
        $invoiced = DB::table('sales_invoice_lines as l')
            ->join('sales_invoices as i', 'i.id', '=', 'l.sales_invoice_id')
            ->where('i.company_id', app(TenantContext::class)->id())
            ->where('i.status', SalesInvoice::STATUS_POSTED)
            ->whereBetween('i.invoice_date', [$from, $to]);
        $credited = DB::table('sales_credit_note_lines as l')
            ->join('sales_credit_notes as c', 'c.id', '=', 'l.sales_credit_note_id')
            ->where('c.company_id', app(TenantContext::class)->id())
            ->where('c.status', SalesCreditNote::STATUS_POSTED)
            ->whereBetween('c.credit_date', [$from, $to]);

        [$key, $label] = match ($group) {
            'product' => ['l.product_id', 'product'],
            'month' => ['period', 'month'],
            default => ['customer_id', 'customer'],
        };

        $select = fn ($q, string $alias, string $dateCol, string $partyCol) => $q->selectRaw(match ($group) {
            'product' => 'l.product_id as k',
            'month' => "DATE_FORMAT({$alias}.{$dateCol}, '%Y-%m') as k",
            default => "{$alias}.{$partyCol} as k",
        }.', SUM(l.quantity) as qty, SUM(l.line_subtotal - l.line_discount) as net, SUM(l.line_tax) as tax, COUNT(DISTINCT '.$alias.'.id) as docs')->groupBy('k');

        $in = $select($invoiced, 'i', 'invoice_date', 'customer_id')->get()->keyBy('k');
        $out = $select($credited, 'c', 'credit_date', 'customer_id')->get()->keyBy('k');
        $keys = $in->keys()->merge($out->keys())->unique();

        $names = match ($group) {
            'product' => DB::table('products')->whereIn('id', $keys)->pluck('name', 'id'),
            'month' => collect(),
            default => DB::table('customers')->whereIn('id', $keys)->pluck('name', 'id'),
        };

        $rows = $keys->map(fn ($k) => [
            'key' => $k,
            'label' => $group === 'month' ? $k : ($names[$k] ?? '#'.$k),
            'quantity' => round((float) ($in[$k]->qty ?? 0) - (float) ($out[$k]->qty ?? 0), 3),
            'invoices' => (int) ($in[$k]->docs ?? 0),
            'gross' => round((float) ($in[$k]->net ?? 0), 2),
            'returns' => round((float) ($out[$k]->net ?? 0), 2),
            'net' => round((float) ($in[$k]->net ?? 0) - (float) ($out[$k]->net ?? 0), 2),
            'tax' => round((float) ($in[$k]->tax ?? 0) - (float) ($out[$k]->tax ?? 0), 2),
        ])->sortBy($group === 'month' ? 'key' : fn ($r) => -$r['net'])->values()->all();

        return [
            'group' => $label,
            'from' => $from,
            'to' => $to,
            'rows' => $rows,
            'total' => [
                'gross' => round(array_sum(array_column($rows, 'gross')), 2),
                'returns' => round(array_sum(array_column($rows, 'returns')), 2),
                'net' => round(array_sum(array_column($rows, 'net')), 2),
                'tax' => round(array_sum(array_column($rows, 'tax')), 2),
            ],
        ];
    }
}
