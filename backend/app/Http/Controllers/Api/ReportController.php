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
    private const KINDS = ['vouchers', 'expenses', 'payments', 'departments', 'employees', 'approvals', 'monthly'];

    /**
     * Which reports each role may run at all.
     *
     * The visibility rules already stop a report returning rows a caller may
     * not see, but that is not the same as being entitled to the report. An
     * employee running an "Employee report" that lawfully contains only their
     * own line is a confusing thing to offer; a cashier wants the money moved,
     * not a turnaround analysis. The catalogue is filtered, and `show` refuses
     * anything outside it rather than trusting the UI to have hidden it.
     */
    private const KINDS_BY_ROLE = [
        User::ROLE_EMPLOYEE => ['vouchers', 'expenses'],
        User::ROLE_CASHIER => ['payments', 'vouchers', 'expenses', 'departments', 'monthly'],
        User::ROLE_FINANCE => ['payments', 'vouchers', 'expenses', 'departments', 'employees', 'approvals', 'monthly'],
    ];

    public function __construct(
        private readonly VoucherVisibility $visibility,
        private readonly StatusPresenter $status,
        private readonly AmountFormatter $money,
        private readonly TenantContext $tenant,
    ) {}

    public function kinds(Request $request)
    {
        return response()->json([
            'data' => array_values($this->catalogueFor($request->user())),
            'scope' => $this->scopeDescriptor($request->user()),
        ]);
    }

    /** The full catalogue, narrowed to what this role may run. */
    private function catalogueFor(User $user): array
    {
        $all = [
            'vouchers' => ['key' => 'vouchers', 'icon' => 'ph-receipt', 'title' => 'Voucher report', 'title_sw' => 'Ripoti ya vocha', 'body' => 'Every voucher with status, approver and amount', 'body_sw' => 'Kila vocha na hali, mwidhinishaji na kiasi'],
            'expenses' => ['key' => 'expenses', 'icon' => 'ph-coins', 'title' => 'Expense report', 'title_sw' => 'Ripoti ya matumizi', 'body' => 'Spend by category and cost centre', 'body_sw' => 'Matumizi kwa kundi na kituo cha gharama'],
            'payments' => ['key' => 'payments', 'icon' => 'ph-wallet', 'title' => 'Payment report', 'title_sw' => 'Ripoti ya malipo', 'body' => 'Money released, by bank and by cash', 'body_sw' => 'Fedha zilizotolewa, kwa benki na kwa taslimu'],
            'departments' => ['key' => 'departments', 'icon' => 'ph-buildings', 'title' => 'Department report', 'title_sw' => 'Ripoti ya idara', 'body' => 'Volume and value per department', 'body_sw' => 'Wingi na thamani kwa kila idara'],
            'employees' => ['key' => 'employees', 'icon' => 'ph-user', 'title' => 'Employee report', 'title_sw' => 'Ripoti ya mfanyakazi', 'body' => 'Requests and outcomes per person', 'body_sw' => 'Maombi na matokeo kwa kila mtu'],
            'approvals' => ['key' => 'approvals', 'icon' => 'ph-list-checks', 'title' => 'Approval report', 'title_sw' => 'Ripoti ya idhini', 'body' => 'Turnaround times and rejection reasons', 'body_sw' => 'Muda wa kushughulikia na sababu za kukataa'],
            'monthly' => ['key' => 'monthly', 'icon' => 'ph-calendar', 'title' => 'Monthly report', 'title_sw' => 'Ripoti ya mwezi', 'body' => 'Month-end pack, ready for the auditor', 'body_sw' => 'Muhtasari wa mwisho wa mwezi, tayari kwa mkaguzi'],
        ];

        $permitted = self::KINDS_BY_ROLE[$user->role] ?? self::KINDS;

        return array_intersect_key($all, array_flip($permitted));
    }

    /**
     * How wide this caller's reporting reaches, in their own words.
     *
     * This is the ceiling, not a filter: a department picker may narrow it and
     * can never widen it, which is enforced in `scopedVouchers` regardless of
     * what the client sends.
     */
    private function scopeDescriptor(User $user): array
    {
        if ($user->isAdmin()) {
            return ['level' => 'company', 'label' => 'Company-wide', 'department_ids' => null];
        }

        if (! $user->isApprover()) {
            return ['level' => 'own', 'label' => 'Your own vouchers only', 'department_ids' => []];
        }

        if (in_array($user->role, [User::ROLE_CEO, User::ROLE_DIRECTOR, User::ROLE_FINANCE, User::ROLE_CASHIER], true)) {
            return ['level' => 'company', 'label' => 'Company-wide', 'department_ids' => null];
        }

        $ids = $user->headedDepartments()->pluck('id')
            ->merge($user->managedDepartments()->pluck('id'))->unique()->values();

        $names = Department::whereIn('id', $ids)->pluck('name')->implode(' · ');

        return [
            'level' => 'departments',
            'label' => $names ?: 'No department assigned',
            'department_ids' => $ids->all(),
        ];
    }

    public function show(Request $request, string $kind)
    {
        abort_unless(in_array($kind, self::KINDS, true), 404, 'Unknown report.');
        abort_unless(
            array_key_exists($kind, $this->catalogueFor($request->user())),
            403,
            'That report is outside your permissions.',
        );

        $request->validate($this->filterRules());

        ['headings' => $headings, 'rows' => $rows, 'summary' => $summary] = $this->build($request, $kind);

        return response()->json([
            'kind' => $kind,
            'scope' => $this->scopeDescriptor($request->user()),
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
        abort_unless(
            array_key_exists($kind, $this->catalogueFor($request->user())),
            403,
            'That report is outside your permissions.',
        );

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
            'payments' => $this->payments($request),
            'departments' => $this->departments($request),
            'employees' => $this->employees($request),
            'approvals' => $this->approvals($request),
            'monthly' => $this->monthly($request),
            default => $this->vouchers($request),
        };
    }

    private function scopedVouchers(Request $request)
    {
        $query = Voucher::query()->with(['requester', 'department', 'voucherType', 'paidBy', 'workflow.steps']);

        $this->visibility->apply($query, $request->user());

        return $query
            ->when($request->query('from'), fn ($q, $v) => $q->whereDate('voucher_date', '>=', $v))
            ->when($request->query('to'), fn ($q, $v) => $q->whereDate('voucher_date', '<=', $v))
            ->when($request->query('department_id'), fn ($q, $v) => $q->where('department_id', $v))
            ->when($request->query('voucher_type_id'), fn ($q, $v) => $q->where('voucher_type_id', $v))
            ->when($request->query('requester_id'), fn ($q, $v) => $q->where('requester_id', $v))
            ->when($request->query('status'), fn ($q, $v) => $q->status($v))
            ->when($request->query('kind'), fn ($q, $v) => $q->kind($v))
            ->when($request->query('payee'), fn ($q, $v) => $q->where('payee', 'like', '%'.$v.'%'))
            ->when($request->query('min_amount'), fn ($q, $v) => $q->where('amount', '>=', $v))
            ->when($request->query('max_amount'), fn ($q, $v) => $q->where('amount', '<=', $v))
            ->when($request->query('payment_method'), fn ($q, $v) => $q->where('payment_method', $v));
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

    /**
     * What the money actually did. Bank and cash are reported side by side
     * because they reconcile against different things — a statement and a
     * float — and a single "paid" column hides which is which.
     */
    private function payments(Request $request): array
    {
        $vouchers = $this->scopedVouchers($request)
            ->whereIn('status', [Voucher::STATUS_APPROVED, Voucher::STATUS_PAID])
            ->with('paidBy')
            ->orderByDesc('payment_date')->orderByDesc('approved_at')
            ->get();

        $rows = $vouchers->map(fn (Voucher $v) => [
            $v->number,
            $v->isBank() ? 'Bank' : 'Cash',
            $v->payment_date?->format('Y-m-d') ?? '—',
            $v->payee,
            $v->department?->name ?? '—',
            (float) $v->amount,
            $v->currency,
            $v->payment_method ?: '—',
            $v->payment_reference ?: ($v->cheque_number ?: '—'),
            $v->paidBy?->name ?? '—',
            $v->isPaid() ? 'Paid' : 'Awaiting payment',
        ])->all();

        $paid = $vouchers->where('status', Voucher::STATUS_PAID);
        $outstanding = $vouchers->where('status', Voucher::STATUS_APPROVED);
        $currency = $this->tenant->company()?->currency ?? 'TZS';

        return [
            'title' => 'Payment report',
            'headings' => ['Number', 'Format', 'Paid on', 'Payee', 'Department', 'Amount', 'Currency', 'Method', 'Reference', 'Paid by', 'Status'],
            'rows' => $rows,
            // The same shape every other report returns, plus the split that
            // only matters here: released vs still outstanding, bank vs cash.
            'summary' => $this->summary($vouchers) + [
                'paid_total' => (float) $paid->sum('amount'),
                'paid_total_text' => $this->money->money((float) $paid->sum('amount'), $currency),
                'paid_count' => $paid->count(),
                'bank_total_text' => $this->money->money((float) $paid->where('kind', Voucher::KIND_BANK)->sum('amount'), $currency),
                'bank_count' => $paid->where('kind', Voucher::KIND_BANK)->count(),
                'cash_total_text' => $this->money->money((float) $paid->where('kind', Voucher::KIND_CASH)->sum('amount'), $currency),
                'cash_count' => $paid->where('kind', Voucher::KIND_CASH)->count(),
                'outstanding_total_text' => $this->money->money((float) $outstanding->sum('amount'), $currency),
                'outstanding_count' => $outstanding->count(),
            ],
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
            'kind' => ['nullable', Rule::in(Voucher::KINDS)],
            'payee' => ['nullable', 'string', 'max:180'],
            'min_amount' => ['nullable', 'numeric'],
            'max_amount' => ['nullable', 'numeric'],
            'payment_method' => ['nullable', 'string', 'max:80'],
        ];
    }
}
