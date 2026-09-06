<?php

namespace App\Http\Controllers\Api;

use App\Exports\TabularExport;
use App\Http\Controllers\Controller;
use App\Models\Department;
use App\Models\User;
use App\Models\Voucher;
use App\Services\AmountFormatter;
use App\Services\StatusPresenter;
use App\Services\VoucherVisibility;
use App\Support\TenantContext;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Maatwebsite\Excel\Facades\Excel;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Reporting and exports. Every report is built on the same visibility rules as the
 * voucher list, so a report can never widen what a role is allowed to see.
 */
class ReportController extends Controller
{
    private const KINDS = ['vouchers', 'expenses', 'departments', 'employees', 'approvals', 'monthly'];

    public function __construct(
        private readonly VoucherVisibility $visibility,
        private readonly StatusPresenter $status,
        private readonly AmountFormatter $money,
        private readonly TenantContext $tenant,
    ) {}

    public function kinds()
    {
        return response()->json([
            'data' => [
                ['key' => 'vouchers', 'icon' => 'ph-receipt', 'title' => 'Voucher report', 'title_sw' => 'Ripoti ya vocha', 'body' => 'Every voucher with status, approver and amount', 'body_sw' => 'Kila vocha na hali, mwidhinishaji na kiasi'],
                ['key' => 'expenses', 'icon' => 'ph-coins', 'title' => 'Expense report', 'title_sw' => 'Ripoti ya matumizi', 'body' => 'Spend by category and cost centre', 'body_sw' => 'Matumizi kwa kundi na kituo cha gharama'],
                ['key' => 'departments', 'icon' => 'ph-buildings', 'title' => 'Department report', 'title_sw' => 'Ripoti ya idara', 'body' => 'Volume and value per department', 'body_sw' => 'Wingi na thamani kwa kila idara'],
                ['key' => 'employees', 'icon' => 'ph-user', 'title' => 'Employee report', 'title_sw' => 'Ripoti ya mfanyakazi', 'body' => 'Requests and outcomes per person', 'body_sw' => 'Maombi na matokeo kwa kila mtu'],
                ['key' => 'approvals', 'icon' => 'ph-list-checks', 'title' => 'Approval report', 'title_sw' => 'Ripoti ya idhini', 'body' => 'Turnaround times and rejection reasons', 'body_sw' => 'Muda wa kushughulikia na sababu za kukataa'],
                ['key' => 'monthly', 'icon' => 'ph-calendar', 'title' => 'Monthly report', 'title_sw' => 'Ripoti ya mwezi', 'body' => 'Month-end pack, ready for the auditor', 'body_sw' => 'Muhtasari wa mwisho wa mwezi, tayari kwa mkaguzi'],
            ],
        ]);
    }

    public function show(Request $request, string $kind)
    {
        abort_unless(in_array($kind, self::KINDS, true), 404, 'Unknown report.');

        $request->validate($this->filterRules());

        ['headings' => $headings, 'rows' => $rows, 'summary' => $summary] = $this->build($request, $kind);

        return response()->json([
            'kind' => $kind,
            'headings' => $headings,
            'rows' => $rows,
            'summary' => $summary,
            'filters' => $request->only(['from', 'to', 'department_id', 'status', 'voucher_type_id', 'requester_id']),
            'generated_at' => now()->toIso8601String(),
        ]);
    }

    /** PDF, Excel or CSV — the three export formats offered on the reports screen. */
    public function export(Request $request, string $kind)
    {
        abort_unless(in_array($kind, self::KINDS, true), 404, 'Unknown report.');

        $request->validate($this->filterRules() + [
            'format' => ['required', Rule::in(['pdf', 'xlsx', 'csv'])],
        ]);

        ['headings' => $headings, 'rows' => $rows, 'summary' => $summary, 'title' => $title] = $this->build($request, $kind);

        $filename = 'vouchflow-'.$kind.'-'.now()->format('Ymd-His');

        return match ($request->query('format')) {
            'pdf' => Pdf::loadView('pdf.report', [
                'title' => $title,
                'company' => $this->tenant->company(),
                'headings' => $headings,
                'rows' => $rows,
                'summary' => $summary,
                'fontPath' => storage_path('fonts'),
                'generatedAt' => now()->format('j M Y, H:i'),
                'range' => $this->rangeLabel($request),
            ])->setPaper('a4', 'landscape')->download($filename.'.pdf'),

            'csv' => $this->csv($headings, $rows, $filename.'.csv'),

            default => Excel::download(new TabularExport($rows, $headings, $title), $filename.'.xlsx'),
        };
    }

    /* --------------------------------------------------------------- builders */

    private function build(Request $request, string $kind): array
    {
        return match ($kind) {
            'expenses' => $this->expenses($request),
            'departments' => $this->departments($request),
            'employees' => $this->employees($request),
            'approvals' => $this->approvals($request),
            'monthly' => $this->monthly($request),
            default => $this->vouchers($request),
        };
    }

    private function scopedVouchers(Request $request)
    {
        $query = Voucher::query()->with(['requester', 'department', 'voucherType', 'workflow.steps']);

        $this->visibility->apply($query, $request->user());

        return $query
            ->when($request->query('from'), fn ($q, $v) => $q->whereDate('voucher_date', '>=', $v))
            ->when($request->query('to'), fn ($q, $v) => $q->whereDate('voucher_date', '<=', $v))
            ->when($request->query('department_id'), fn ($q, $v) => $q->where('department_id', $v))
            ->when($request->query('voucher_type_id'), fn ($q, $v) => $q->where('voucher_type_id', $v))
            ->when($request->query('requester_id'), fn ($q, $v) => $q->where('requester_id', $v))
            ->when($request->query('status'), fn ($q, $v) => $q->status($v));
    }

    private function vouchers(Request $request): array
    {
        $vouchers = $this->scopedVouchers($request)->orderByDesc('voucher_date')->get();

        $rows = $vouchers->map(fn (Voucher $v) => [
            $v->number,
            $v->voucher_date?->format('Y-m-d'),
            $v->voucherType?->name,
            $v->department?->name ?? '—',
            $v->requester?->name ?? '—',
            $v->payee,
            $v->purpose,
            (float) $v->amount,
            $v->currency,
            $this->status->present($v)['label'],
        ])->all();

        return [
            'title' => 'Voucher report',
            'headings' => ['Number', 'Date', 'Type', 'Department', 'Requester', 'Payee', 'Purpose', 'Amount', 'Currency', 'Status'],
            'rows' => $rows,
            'summary' => $this->summary($vouchers),
        ];
    }

    private function expenses(Request $request): array
    {
        $vouchers = $this->scopedVouchers($request)->where('status', Voucher::STATUS_APPROVED)->get();

        $rows = $vouchers->groupBy(fn (Voucher $v) => $v->category ?: 'Uncategorised')
            ->map(fn ($group, $category) => [
                $category,
                $group->pluck('cost_centre')->filter()->unique()->implode(', ') ?: '—',
                $group->count(),
                (float) $group->sum('amount'),
            ])
            ->sortByDesc(fn ($row) => $row[3])
            ->values()->all();

        return [
            'title' => 'Expense report',
            'headings' => ['Category', 'Cost centres', 'Vouchers', 'Approved value'],
            'rows' => $rows,
            'summary' => $this->summary($vouchers),
        ];
    }

    private function departments(Request $request): array
    {
        $vouchers = $this->scopedVouchers($request)->get();

        $rows = Department::orderBy('name')->get()->map(function (Department $d) use ($vouchers) {
            $group = $vouchers->where('department_id', $d->id);

            return [
                $d->name,
                $d->hod?->name ?? '—',
                $d->manager?->name ?? '—',
                $group->count(),
                (float) $group->where('status', Voucher::STATUS_APPROVED)->sum('amount'),
                (float) $group->where('status', Voucher::STATUS_IN_REVIEW)->sum('amount'),
            ];
        })->all();

        return [
            'title' => 'Department report',
            'headings' => ['Department', 'Head of department', 'Manager', 'Vouchers', 'Approved value', 'Pending value'],
            'rows' => $rows,
            'summary' => $this->summary($vouchers),
        ];
    }

    private function employees(Request $request): array
    {
        $vouchers = $this->scopedVouchers($request)->get();

        $rows = $vouchers->groupBy('requester_id')->map(function ($group) {
            $first = $group->first();

            return [
                $first->requester?->name ?? '—',
                $first->requester?->employee_code ?? '—',
                $first->department?->name ?? '—',
                $group->count(),
                $group->where('status', Voucher::STATUS_APPROVED)->count(),
                $group->where('status', Voucher::STATUS_REJECTED)->count(),
                (float) $group->sum('amount'),
            ];
        })->sortByDesc(fn ($row) => $row[6])->values()->all();

        return [
            'title' => 'Employee report',
            'headings' => ['Employee', 'Employee ID', 'Department', 'Requests', 'Approved', 'Rejected', 'Total value'],
            'rows' => $rows,
            'summary' => $this->summary($vouchers),
        ];
    }

    private function approvals(Request $request): array
    {
        $vouchers = $this->scopedVouchers($request)
            ->with('approvals.actor')
            ->whereNotNull('submitted_at')
            ->get();

        $rows = $vouchers->map(function (Voucher $v) {
            $decision = $v->approvals->last(fn ($a) => in_array($a->action, ['approved', 'rejected', 'changes_requested'], true));
            $hours = $v->submitted_at && $decision ? $v->submitted_at->diffInHours($decision->acted_at) : null;

            return [
                $v->number,
                $v->requester?->name ?? '—',
                $v->submitted_at?->format('Y-m-d H:i'),
                $decision?->acted_at?->format('Y-m-d H:i') ?? 'Pending',
                $decision?->actor_name ?? '—',
                $this->status->present($v)['label'],
                $hours !== null ? round($hours / 24, 2) : null,
                $decision?->comment ?? '',
            ];
        })->all();

        return [
            'title' => 'Approval report',
            'headings' => ['Number', 'Requester', 'Submitted', 'Decided', 'Decided by', 'Outcome', 'Turnaround (days)', 'Reason'],
            'rows' => $rows,
            'summary' => $this->summary($vouchers),
        ];
    }

    private function monthly(Request $request): array
    {
        $vouchers = $this->scopedVouchers($request)->get();

        $rows = $vouchers->groupBy(fn (Voucher $v) => $v->voucher_date?->format('Y-m'))
            ->map(fn ($group, $period) => [
                $period,
                $group->count(),
                $group->where('status', Voucher::STATUS_APPROVED)->count(),
                $group->where('status', Voucher::STATUS_REJECTED)->count(),
                $group->where('status', Voucher::STATUS_IN_REVIEW)->count(),
                (float) $group->sum('amount'),
                (float) $group->where('status', Voucher::STATUS_APPROVED)->sum('amount'),
            ])
            ->sortKeys()->values()->all();

        return [
            'title' => 'Monthly report',
            'headings' => ['Period', 'Vouchers', 'Approved', 'Rejected', 'Pending', 'Requested value', 'Approved value'],
            'rows' => $rows,
            'summary' => $this->summary($vouchers),
        ];
    }

    private function summary($vouchers): array
    {
        $currency = $this->tenant->company()?->currency ?? 'TZS';
        $total = (float) $vouchers->sum('amount');
        $approved = (float) $vouchers->where('status', Voucher::STATUS_APPROVED)->sum('amount');

        return [
            'count' => $vouchers->count(),
            'total' => $total,
            'total_text' => $this->money->money($total, $currency),
            'approved_total' => $approved,
            'approved_total_text' => $this->money->money($approved, $currency),
            'currency' => $currency,
        ];
    }

    private function csv(array $headings, array $rows, string $filename): StreamedResponse
    {
        return response()->streamDownload(function () use ($headings, $rows) {
            $out = fopen('php://output', 'w');
            fprintf($out, "\xEF\xBB\xBF"); // BOM, so Excel reads UTF-8 correctly
            fputcsv($out, $headings);

            foreach ($rows as $row) {
                fputcsv($out, $row);
            }

            fclose($out);
        }, $filename, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    private function rangeLabel(Request $request): string
    {
        $from = $request->query('from');
        $to = $request->query('to');

        return $from || $to
            ? trim(($from ?: '…').' – '.($to ?: '…'))
            : 'All time';
    }

    private function filterRules(): array
    {
        return [
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
            'department_id' => ['nullable', 'integer'],
            'voucher_type_id' => ['nullable', 'integer'],
            'requester_id' => ['nullable', 'integer'],
            'status' => ['nullable', 'string'],
        ];
    }
}
