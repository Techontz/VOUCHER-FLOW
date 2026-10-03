<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\VoucherResource;
use App\Models\Company;
use App\Models\Department;
use App\Models\Invoice;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherApproval;
use App\Models\VoucherPayment;
use App\Models\Workflow;
use App\Models\WorkflowStep;
use App\Services\AmountFormatter;
use App\Services\VoucherVisibility;
use App\Services\WorkflowEngine;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Role-shaped dashboards.
 *
 * Every tenant dashboard answers two questions, in this order: what is waiting
 * on *you* right now (the attention banner and the action queue), and how your
 * voucher activity stands (figures and recent activity). The queue empties as
 * the user acts; the figures are history, always computed from the vouchers
 * this user is entitled to see through {@see VoucherVisibility}.
 *
 * Which dashboard a user gets is decided by what their workflow steps allow
 * them to do, not only by their job title: anyone holding a paying step gets
 * the payment desk, an approver whose steps only sign gets the HOD desk.
 *
 * Every figure carries a stable `key` (plus `params`) next to its English
 * `label`, so the web and mobile clients can translate it; clients fall back to
 * the English label for any key they do not know.
 *
 * Payload (tenant views):
 *   role, greeting,
 *   data: view, headline, sub, banner{count,key,params,title,body_key,body,action},
 *         stats[{key,params,label,value,sub,sub_key,sub_params}],
 *         queue, queue_total_text, recent_activity[], recent_activity_key,
 *         recent_activity_label, and per-view extras (see each method).
 */
class DashboardController extends Controller
{
    /** How long a voucher may sit on one step before an admin should look. */
    private const STALL_DAYS = 3;

    /** How many activity rows a dashboard shows. */
    private const ACTIVITY_LIMIT = 8;

    /** Workflow events worth showing as activity; "forwarded" duplicates "signed". */
    private const ACTIVITY_ACTIONS = [
        'created', 'submitted', 'resubmitted', 'signed', 'approved',
        'rejected', 'changes_requested', 'paid', 'cancelled',
    ];

    /** English wording of each activity action: "{actor} {action} {voucher}". */
    private const ACTION_LABELS = [
        'created' => 'created',
        'submitted' => 'submitted',
        'resubmitted' => 'resubmitted',
        'signed' => 'signed',
        'forwarded' => 'forwarded',
        'approved' => 'approved',
        'rejected' => 'rejected',
        'changes_requested' => 'requested changes on',
        'paid' => 'paid',
        'cancelled' => 'cancelled',
    ];

    private const RELATIONS = ['requester', 'department', 'voucherType', 'paidBy', 'workflow.steps'];

    public function __construct(
        private readonly VoucherVisibility $visibility,
        private readonly AmountFormatter $money,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json([
            'role' => $user->role,
            'greeting' => $this->greeting(),
            'data' => match (true) {
                $user->isSuperAdmin() && ! $this->tenant->hasTenant() => $this->platform(),
                $user->isCompanyAdmin() || $user->isSuperAdmin() => $this->admin(),
                // Checked before the approver branches: a cashier holds no
                // review step, so "waiting on me" means approved and unpaid.
                $this->paysMoney($user) => $this->cashier($user),
                $user->isApprover() && $this->signsOnly($user) => $this->hod($user),
                $user->isApprover() => $this->approver($user),
                default => $this->employee($user),
            },
        ]);
    }

    /* ------------------------------------------------------------- employee */

    /**
     * Extras: none beyond the shared keys. `recent_activity` is every workflow
     * event on the employee's own vouchers.
     */
    private function employee(User $user): array
    {
        $mine = Voucher::where('requester_id', $user->id);

        // The employee's own move: finish a draft, or answer a request for changes.
        $queue = Voucher::with(self::RELATIONS)
            ->where('requester_id', $user->id)
            ->whereIn('status', [Voucher::STATUS_DRAFT, Voucher::STATUS_CHANGES_REQUESTED])
            ->orderByDesc('voucher_date')->orderByDesc('id')
            ->get();

        $count = fn (array $statuses) => (clone $mine)->whereIn('status', $statuses)->count();
        $value = fn (array $statuses) => (float) (clone $mine)->whereIn('status', $statuses)->sum('amount');

        $raised = (clone $mine)
            ->whereNotIn('status', [Voucher::STATUS_DRAFT, Voucher::STATUS_CANCELLED])
            ->whereYear('voucher_date', now()->year);

        return $this->tenantView('employee', $queue, [
            $this->stat('dash.stat.myVouchers', 'My vouchers', (string) (clone $mine)->count(), 'dash.sub.allTime', 'All time'),
            $this->stat('dash.stat.pending', 'Pending', (string) $count([Voucher::STATUS_IN_REVIEW]),
                subKey: 'dash.sub.inWorkflow', subLabel: 'In the approval workflow'),
            $this->stat('dash.stat.approved', 'Approved', (string) $count([Voucher::STATUS_APPROVED]),
                subKey: 'dash.sub.awaitingPayment', subLabel: 'Awaiting payment'),
            $this->stat('dash.stat.rejected', 'Rejected', (string) $count([Voucher::STATUS_REJECTED]), 'dash.sub.allTime', 'All time'),
            $this->stat('dash.stat.paidVouchers', 'Paid vouchers', (string) $count([Voucher::STATUS_PAID]),
                subText: $this->format($value([Voucher::STATUS_PAID]))),
            $this->stat('dash.stat.amountRaised', 'Amount raised', $this->format((float) (clone $raised)->sum('amount')),
                'dash.sub.vouchersThisYear', ':count submitted in :year', ['count' => (clone $raised)->count(), 'year' => now()->year]),
        ], $this->activity($mine, 'dash.activity.mine', 'My recent activity'));
    }

    /* ------------------------------------------------------------------ hod */

    /**
     * An approver whose workflow steps sign but never decide.
     *
     * Extras: `recently_signed` (the vouchers this user signed most recently)
     * and `departments` (each headed department's approved-and-paid value).
     */
    private function hod(User $user): array
    {
        $pending = $this->pendingFor($user);
        $departments = $this->scopedDepartments($user);
        $departmentIds = $departments->pluck('id')->all();
        $month = $this->month();

        $signedThisMonth = VoucherApproval::query()
            ->where('actor_id', $user->id)
            ->where('action', 'signed')
            ->whereBetween('acted_at', $month)
            ->distinct()->count('voucher_id');

        $departmentVouchers = Voucher::whereIn('department_id', $departmentIds)
            ->where('status', '!=', Voucher::STATUS_DRAFT);

        $submittedThisMonth = (clone $departmentVouchers)->whereBetween('submitted_at', $month);
        $valueThisMonth = (float) (clone $departmentVouchers)->whereBetween('approved_at', $month)->sum('amount');

        $stats = [
            $this->stat('dash.stat.awaitingSignature', 'Awaiting your signature', (string) $pending->count(),
                subText: $this->format((float) $pending->sum('amount'))),
            $this->stat('dash.stat.signedThisMonth', 'Signed this month', (string) $signedThisMonth,
                'dash.sub.signedByYou', 'Vouchers you signed'),
            $this->stat('dash.stat.deptVouchersThisMonth', 'Department vouchers this month', (string) (clone $submittedThisMonth)->count(),
                subText: $this->format((float) (clone $submittedThisMonth)->sum('amount'))),
            $this->stat('dash.stat.deptValue', 'Department voucher value', $this->format($valueThisMonth),
                'dash.sub.approvedPaidThisMonth', 'Approved and paid this month'),
        ];

        // One figure per department they head — capped, so a head of many
        // departments gets a readable row rather than a wall of tiles.
        $perDepartment = $departments->take(3)->map(function (Department $department) {
            $value = (float) Voucher::where('department_id', $department->id)
                ->whereNotNull('approved_at')
                ->whereYear('approved_at', now()->year)
                ->sum('amount');

            return [
                'id' => $department->id,
                'name' => $department->name,
                'total' => $value,
                'total_text' => $this->format($value),
            ];
        })->values();

        foreach ($perDepartment as $row) {
            $stats[] = $this->stat('dash.stat.deptExpenses', "{$row['name']} expenses", $row['total_text'],
                'dash.sub.approvedPaidThisYear', 'Approved and paid in :year', ['year' => now()->year],
                params: ['department' => $row['name']]);
        }

        $recentlySigned = Voucher::query()
            ->select('vouchers.*')
            ->join('voucher_approvals', 'voucher_approvals.voucher_id', '=', 'vouchers.id')
            ->where('voucher_approvals.actor_id', $user->id)
            ->where('voucher_approvals.action', 'signed')
            ->orderByDesc('voucher_approvals.acted_at')
            ->limit(5)
            ->get()
            ->unique('id')
            ->map(fn (Voucher $v) => [
                'id' => $v->id,
                'number' => $v->number,
                'payee' => $v->payee,
                'amount_text' => $this->money->money((float) $v->amount, $v->currency ?: $this->currency()),
                'status' => $v->status,
            ])->values();

        return $this->tenantView('hod', $pending, $stats,
            $this->activity($this->visible($user), 'dash.activity.department', 'Recent department activity'),
            [
                'recently_signed' => $recentlySigned,
                'departments' => $perDepartment,
            ]);
    }

    /* ------------------------------------------------------------- approver */

    /**
     * Managers, CEOs, directors and finance officers who decide.
     *
     * Extras: `by_department` — approved and paid value this month, per
     * department, across the vouchers this approver can see.
     */
    private function approver(User $user): array
    {
        $pending = $this->pendingFor($user);
        $month = $this->month();

        $actedThisMonth = fn (string $action) => VoucherApproval::query()
            ->where('actor_id', $user->id)
            ->where('action', $action)
            ->whereBetween('acted_at', $month);

        $approvedIds = $actedThisMonth('approved')->distinct()->pluck('voucher_id');
        $approvedValue = (float) Voucher::whereIn('id', $approvedIds)->sum('amount');

        return $this->tenantView('approver', $pending, [
            $this->stat('dash.stat.awaitingApproval', 'Awaiting your approval', (string) $pending->count(),
                subText: $this->format((float) $pending->sum('amount'))),
            $this->stat('dash.stat.approvedThisMonth', 'Approved this month', (string) $approvedIds->count(),
                'dash.sub.approvedByYou', 'Approved by you'),
            $this->stat('dash.stat.rejectedThisMonth', 'Rejected this month', (string) $actedThisMonth('rejected')->distinct()->count('voucher_id'),
                'dash.sub.rejectedByYou', 'Rejected by you'),
            $this->stat('dash.stat.totalValue', 'Total voucher value', $this->format($approvedValue),
                'dash.sub.approvedByYouThisMonth', 'Approved by you this month'),
        ], $this->activity($this->visible($user), 'dash.activity.approvals', 'Recent approval activity',
            ['signed', 'approved', 'rejected', 'changes_requested', 'paid']),
            [
                'by_department' => $this->departmentSpend($this->visible($user)->whereBetween('vouchers.approved_at', $month), false),
            ]);
    }

    /* -------------------------------------------------------------- cashier */

    /**
     * Whoever the workflow entrusts with releasing money.
     *
     * Extras: `payment_totals` — paid this month in total and by bank and cash,
     * each as {count, total, total_text}.
     */
    private function cashier(User $user): array
    {
        $engine = app(WorkflowEngine::class);

        $query = Voucher::with(self::RELATIONS)->awaitingPayment();
        $this->visibility->apply($query, $user);

        $queue = $query->orderBy('approved_at')->get()
            ->filter(fn (Voucher $v) => $engine->canPay($user, $v))
            ->values();

        $bank = $queue->where('kind', Voucher::KIND_BANK);
        $cash = $queue->where('kind', Voucher::KIND_CASH);

        $paidThisMonth = $this->visible($user)
            ->where('vouchers.status', Voucher::STATUS_PAID)
            ->whereBetween('vouchers.paid_at', $this->month())
            ->get(['vouchers.id', 'vouchers.amount', 'vouchers.kind']);

        // Money is released in parts, so "paid this month" is every payment made
        // this month — part payments included — and what is owed is the balance.
        $released = VoucherPayment::query()
            ->whereIn('voucher_id', $this->visible($user)->pluck('vouchers.id'))
            ->whereBetween('paid_at', $this->month())
            ->with('voucher:id,kind')
            ->get()
            ->map(fn (VoucherPayment $p) => (object) ['amount' => (float) $p->amount, 'kind' => $p->voucher?->kind]);
        $owed = fn (Collection $rows) => (float) $rows->sum(fn (Voucher $v) => $v->balance());

        $totals = fn (Collection $rows) => [
            'count' => $rows->count(),
            'total' => (float) $rows->sum('amount'),
            'total_text' => $this->format((float) $rows->sum('amount')),
        ];

        return $this->tenantView('cashier', $queue, [
            $this->stat('dash.stat.awaitingPayment', 'Awaiting payment', (string) $queue->count(),
                'dash.sub.approvedUnpaid', 'Approved, not yet paid'),
            $this->stat('dash.stat.pendingPayments', 'Pending payments', $this->format($owed($queue)),
                'dash.sub.bankCash', 'Bank :bank · Cash :cash',
                ['bank' => $this->format($owed($bank)), 'cash' => $this->format($owed($cash))]),
            $this->stat('dash.stat.paidVouchers', 'Paid vouchers', (string) $paidThisMonth->count(),
                'dash.sub.thisMonth', 'This month'),
            $this->stat('dash.stat.paidThisMonth', 'Paid this month', $this->format((float) $released->sum('amount')),
                'dash.sub.bankCash', 'Bank :bank · Cash :cash',
                [
                    'bank' => $this->format((float) $released->where('kind', Voucher::KIND_BANK)->sum('amount')),
                    'cash' => $this->format((float) $released->where('kind', Voucher::KIND_CASH)->sum('amount')),
                ]),
        ], $this->activity($this->visible($user), 'dash.activity.payments', 'Recent payment activity', ['paid', 'part_paid']),
            [
                'payment_totals' => [
                    'paid' => $totals($released),
                    'bank' => $totals($released->where('kind', Voucher::KIND_BANK)),
                    'cash' => $totals($released->where('kind', Voucher::KIND_CASH)),
                ],
            ]);
    }

    /** Whether any step in this tenant's workflows gives this user the money. */
    private function paysMoney(User $user): bool
    {
        if (! $user->company_id || $user->isAdmin()) {
            return false;
        }

        return $this->stepsHeldBy($user)->contains(fn (WorkflowStep $step) => (bool) $step->can_pay);
    }

    /**
     * Whether every step this user holds signs without deciding.
     *
     * Derived from the steps, not from whatever happens to be in the queue: an
     * HOD whose queue is momentarily empty still signs only.
     */
    private function signsOnly(User $user): bool
    {
        $steps = $this->stepsHeldBy($user);

        return $steps->isNotEmpty() && $steps->every(fn (WorkflowStep $step) => ! $step->can_approve);
    }

    /** @return Collection<int,WorkflowStep> */
    private function stepsHeldBy(User $user): Collection
    {
        return WorkflowStep::query()
            ->whereHas('workflow', fn ($w) => $w->where('company_id', $user->company_id)->where('is_active', true))
            ->where(fn ($q) => $q->where('assigned_user_id', $user->id)
                ->orWhere(fn ($r) => $r->whereNull('assigned_user_id')->where('role', $user->role)))
            ->get();
    }

    /* ---------------------------------------------------------------- admin */

    /**
     * Extras: `overview` {active_users, departments}, `workflow` (the default
     * route and its steps in order), `subscription`, `volume` and
     * `by_department` (approved and paid, all time).
     */
    private function admin(): array
    {
        // An administrator's queue is what has STOPPED: vouchers sitting on the
        // same step long enough that someone has to go and unblock them.
        $stalled = Voucher::with(self::RELATIONS)
            ->where('status', Voucher::STATUS_IN_REVIEW)
            ->where(fn ($q) => $q
                ->where('updated_at', '<=', now()->subDays(self::STALL_DAYS))
                ->orWhere(fn ($r) => $r->whereNull('updated_at')
                    ->where('submitted_at', '<=', now()->subDays(self::STALL_DAYS))))
            ->orderBy('updated_at')
            ->get();

        $submitted = Voucher::whereNotIn('status', [Voucher::STATUS_DRAFT]);
        $total = (clone $submitted)->count();
        $inReview = Voucher::where('status', Voucher::STATUS_IN_REVIEW);
        $approved = (clone $submitted)->whereNotNull('approved_at')->count();
        $paid = Voucher::where('status', Voucher::STATUS_PAID);
        $rejected = Voucher::where('status', Voucher::STATUS_REJECTED)->count();
        $share = fn (int $n) => $total ? (int) round($n / $total * 100) : 0;

        $thisMonth = (float) (clone $submitted)->whereBetween('voucher_date', $this->month())->sum('amount');
        $lastMonth = (float) (clone $submitted)->whereBetween('voucher_date', [
            now()->subMonthNoOverflow()->startOfMonth(), now()->subMonthNoOverflow()->endOfMonth(),
        ])->sum('amount');

        $activeUsers = User::where('company_id', $this->tenant->id())->where('status', 'active')->count();
        $departments = Department::count();

        return $this->tenantView('admin', $stalled, [
            $this->stat('dash.stat.activeUsers', 'Active users', (string) $activeUsers,
                'dash.sub.departments', ':count departments', ['count' => $departments]),
            $this->stat('dash.stat.submittedVouchers', 'Submitted vouchers', (string) $total, 'dash.sub.allTime', 'All time'),
            $this->stat('dash.stat.inWorkflow', 'In the workflow', (string) (clone $inReview)->count(),
                subText: $this->format((float) (clone $inReview)->sum('amount'))),
            $this->stat('dash.stat.approvedIncludingPaid', 'Approved (including paid)', (string) $approved,
                'dash.sub.percentOfSubmitted', ':percent% of submitted', ['percent' => $share($approved)]),
            $this->stat('dash.stat.paidVouchers', 'Paid vouchers', (string) (clone $paid)->count(),
                subText: $this->format((float) (clone $paid)->sum('amount'))),
            $this->stat('dash.stat.rejected', 'Rejected', (string) $rejected,
                'dash.sub.percentOfSubmitted', ':percent% of submitted', ['percent' => $share($rejected)]),
            $this->stat('dash.stat.valueThisMonth', 'Value this month', $this->format($thisMonth),
                $lastMonth > 0 ? 'dash.sub.vsLastMonth' : 'dash.sub.noPriorMonth',
                $lastMonth > 0 ? ':amount last month' : 'No vouchers last month',
                $lastMonth > 0 ? ['amount' => $this->format($lastMonth)] : []),
            $this->stat('dash.stat.avgApprovalTime', 'Average approval time', $this->averageApproval() ?? '—',
                'dash.sub.submissionToApproval', 'From submission to approval'),
        ], $this->activity(Voucher::query(), 'dash.activity.company', 'Recent activity'),
            [
                'overview' => ['active_users' => $activeUsers, 'departments' => $departments],
                'workflow' => $this->defaultWorkflow(),
                'subscription' => $this->subscription(),
                'volume' => $this->monthlyVolume(),
                'by_department' => $this->departmentSpend(Voucher::query(), true),
            ]);
    }

    /** The default route, its steps in order, for the admin's workflow card. */
    private function defaultWorkflow(): ?array
    {
        $workflow = Workflow::with('steps')
            ->where('is_default', true)
            ->where('is_active', true)
            ->latest('id')
            ->first();

        if (! $workflow) {
            return null;
        }

        return [
            'id' => $workflow->id,
            'name' => $workflow->name,
            'name_sw' => $workflow->name_sw ?? null,
            'steps' => $workflow->steps->map(fn (WorkflowStep $step) => [
                'position' => $step->position,
                'name' => $step->name,
                'name_sw' => $step->name_sw,
                'role' => $step->role,
                'action' => match (true) {
                    $step->isRequestStep() => 'request',
                    $step->can_approve => 'approve',
                    (bool) $step->can_pay => 'pay',
                    (bool) $step->can_sign => 'sign',
                    default => 'review',
                },
            ])->values(),
        ];
    }

    private function subscription(): ?array
    {
        $company = $this->tenant->company();

        if (! $company) {
            return null;
        }

        $company->loadMissing('plan');

        return [
            'plan' => $company->plan?->name,
            'status' => $company->status,
            'trial_ends_at' => $company->trial_ends_at?->toIso8601String(),
            'renews_at' => $company->current_period_end?->toIso8601String(),
            'days_remaining' => $company->daysRemaining(),
        ];
    }

    /* ------------------------------------------------------------- platform */

    private function platform(): array
    {
        $companies = Company::count();
        $active = Company::where('status', 'active')->count();
        $trial = Company::where('status', 'trial')->count();
        $pastDue = Company::whereIn('status', ['past_due', 'suspended'])->count();
        $pending = Company::where('status', Company::STATUS_PENDING)->count();

        $users = User::whereNotNull('company_id')->count();
        $vouchers = Voucher::query()->withoutGlobalScopes()->count();

        $revenue = (float) Invoice::query()->withoutGlobalScopes()
            ->where('status', 'paid')
            ->whereBetween('paid_at', $this->month())
            ->sum('total');

        $runRate = (float) Invoice::query()->withoutGlobalScopes()
            ->where('status', 'paid')
            ->where('paid_at', '>=', now()->subYear())
            ->sum('total');

        $status = fn (string $s) => Voucher::query()->withoutGlobalScopes()->where('status', $s)->count();

        return [
            'view' => 'platform',
            'headline' => "{$companies} companies · ".number_format($users).' users · '.number_format($vouchers).' vouchers',
            'sub' => 'Monthly revenue '.$this->money->money($revenue, 'TZS')
                .($pending ? " · {$pending} awaiting approval" : '')
                .($pastDue ? " · {$pastDue} accounts need attention." : '.'),
            'banner' => null,
            'stats' => [
                $this->stat('dash.stat.totalCompanies', 'Total companies', (string) $companies,
                    'dash.sub.companyMix', ':active active · :trial on trial · :atRisk at risk',
                    ['active' => $active, 'trial' => $trial, 'atRisk' => $pastDue]),
                $this->stat('dash.stat.monthlyRevenue', 'Monthly revenue', $this->money->money($revenue, 'TZS'),
                    'dash.sub.invoicesPaidThisMonth', 'Invoices paid this month'),
                $this->stat('dash.stat.trailingRevenue', 'Revenue, last 12 months', $this->money->money($runRate, 'TZS'),
                    'dash.sub.collected', 'Collected'),
                $this->stat('dash.stat.totalUsers', 'Total users', number_format($users), 'dash.sub.acrossCompanies', 'Across all companies'),
                $this->stat('dash.stat.totalVouchers', 'Total vouchers', number_format($vouchers), 'dash.sub.platformWide', 'Platform-wide'),
                $this->stat('dash.stat.pendingApprovedRejected', 'Pending / approved / rejected',
                    $status(Voucher::STATUS_IN_REVIEW).' / '.$status(Voucher::STATUS_APPROVED).' / '.$status(Voucher::STATUS_REJECTED),
                    'dash.sub.platformWide', 'Platform-wide'),
            ],
            'pending_companies' => $pending,
            // Companies the operator has to act on: registrations waiting for
            // approval first (oldest first), then accounts in arrears or suspended.
            'attention' => $this->companiesNeedingAttention(),
            'recent_companies' => Company::with('plan')->withCount(['users', 'vouchers'])->latest('id')->limit(6)->get()
                ->map(fn (Company $c) => [
                    'id' => $c->id, 'name' => $c->name, 'plan' => $c->plan?->name,
                    'status' => $c->status, 'users_count' => $c->users_count, 'vouchers_count' => $c->vouchers_count,
                    'created_at' => $c->created_at?->toIso8601String(),
                ]),
            'recent_payments' => Invoice::query()->withoutGlobalScopes()->with('company')->latest('id')->limit(6)->get()
                ->map(fn (Invoice $i) => [
                    'id' => $i->id, 'number' => $i->number, 'company' => $i->company?->name,
                    'total' => (float) $i->total, 'currency' => $i->currency,
                    'status' => $i->status, 'method' => $i->method,
                    'created_at' => $i->created_at?->toIso8601String(),
                ]),
        ];
    }

    /** @return list<array<string,mixed>> */
    private function companiesNeedingAttention(): array
    {
        $row = fn (Company $c) => [
            'id' => $c->id, 'name' => $c->name, 'plan' => $c->plan?->name,
            'status' => $c->status, 'email' => $c->email,
            'users_count' => $c->users_count, 'vouchers_count' => $c->vouchers_count,
            'current_period_end' => $c->current_period_end?->toIso8601String(),
            'created_at' => $c->created_at?->toIso8601String(),
        ];

        $pending = Company::with('plan')->withCount(['users', 'vouchers'])
            ->where('status', Company::STATUS_PENDING)
            ->oldest('id')->limit(20)->get();

        $atRisk = Company::with('plan')->withCount(['users', 'vouchers'])
            ->whereIn('status', ['past_due', 'suspended'])
            ->latest('updated_at')->limit(10)->get();

        return $pending->concat($atRisk)->map($row)->values()->all();
    }

    /* ----------------------------------------------------- shared structure */

    /**
     * The common tenant payload: banner, figures, queue and recent activity.
     *
     * `headline` and `sub` repeat the banner's wording for older clients.
     */
    private function tenantView(string $view, Collection $queue, array $stats, array $activity, array $extra = []): array
    {
        $banner = $this->banner($view, $queue->count());

        return array_merge([
            'view' => $view,
            'headline' => $banner['title'],
            'sub' => $banner['body'],
            'banner' => $banner,
            'stats' => $stats,
            'queue' => VoucherResource::collection($queue),
            'queue_total_text' => $this->format((float) $queue->sum('amount')),
        ], $activity, $extra);
    }

    /**
     * The attention banner: how many vouchers are waiting on this user, and
     * where to go — or, when nothing is, a plain statement of why.
     *
     * @return array{count:int,key:string,params:array,title:string,body_key:string,body:string,action:?array}
     */
    private function banner(string $view, int $count): array
    {
        $pending = [
            'employee' => ['Complete your drafts and respond to any requested changes to keep them moving.', 'dash.cta.continue', 'Continue drafts and returns'],
            'hod' => ['Each one needs your signature before it can move to the approval step.', 'dash.cta.sign', 'Sign vouchers'],
            'approver' => ['Each one has reached your approval step.', 'dash.cta.approve', 'Review and approve'],
            'cashier' => ['Each one is approved and ready for payment.', 'dash.cta.pay', 'Record payments'],
            'admin' => ['These have remained on the same step for '.self::STALL_DAYS.' days or more.', 'dash.cta.stalled', 'Review stalled vouchers'],
        ];

        $clear = [
            'employee' => "Everything you've submitted is currently being processed or has already been reviewed.",
            'hod' => 'No vouchers are waiting for your signature.',
            'approver' => 'No vouchers are waiting for your approval.',
            'cashier' => 'Every approved voucher has been paid.',
            'admin' => 'No vouchers have stalled in the workflow.',
        ];

        if ($count === 0) {
            return [
                'count' => 0,
                'key' => 'dash.banner.clear',
                'params' => [],
                'title' => 'Nothing needs your attention.',
                'body_key' => "dash.banner.clear.{$view}",
                'body' => $clear[$view],
                'action' => null,
            ];
        }

        [$body, $actionKey, $actionLabel] = $pending[$view];

        return [
            'count' => $count,
            'key' => $count === 1 ? 'dash.banner.pending.one' : 'dash.banner.pending.other',
            'params' => ['count' => $count],
            'title' => $count === 1
                ? 'You have 1 voucher waiting for your attention.'
                : "You have {$count} vouchers waiting for your attention.",
            'body_key' => "dash.banner.pending.{$view}",
            'body' => $body,
            'action' => ['key' => $actionKey, 'label' => $actionLabel, 'href' => '#queue'],
        ];
    }

    /**
     * One figure. `:name` placeholders in the sub label are filled from
     * `sub_params`, so a client translating `sub_key` has the same values.
     */
    private function stat(
        string $key,
        string $label,
        string $value,
        ?string $subKey = null,
        ?string $subLabel = null,
        array $subParams = [],
        ?string $subText = null,
        array $params = [],
    ): array {
        $sub = $subText ?? ($subLabel !== null ? $this->fill($subLabel, $subParams) : '');

        return [
            'key' => $key,
            'params' => (object) $params,
            'label' => $label,
            'value' => $value,
            'sub' => $sub,
            'sub_key' => $subText !== null ? null : $subKey,
            'sub_params' => (object) $subParams,
        ];
    }

    private function fill(string $text, array $params): string
    {
        foreach ($params as $name => $value) {
            $text = str_replace(':'.$name, (string) $value, $text);
        }

        return $text;
    }

    /**
     * The latest workflow events on the given vouchers.
     *
     * @param  Builder<Voucher>  $vouchers  already narrowed to what the caller may see
     */
    private function activity(Builder $vouchers, string $key, string $label, ?array $actions = null): array
    {
        $ids = (clone $vouchers)->select('vouchers.id');

        $rows = VoucherApproval::query()
            ->with('voucher:id,number,amount,currency,status')
            ->whereIn('voucher_id', $ids)
            ->whereIn('action', $actions ?? self::ACTIVITY_ACTIONS)
            ->orderByDesc('acted_at')->orderByDesc('id')
            ->limit(self::ACTIVITY_LIMIT)
            ->get();

        return [
            'recent_activity_key' => $key,
            'recent_activity_label' => $label,
            'recent_activity' => $rows->map(fn (VoucherApproval $a) => [
                'id' => $a->id,
                'action' => $a->action,
                'action_label' => self::ACTION_LABELS[$a->action] ?? str_replace('_', ' ', $a->action),
                'actor_id' => $a->actor_id,
                'actor' => $a->actor_name,
                'voucher_id' => $a->voucher_id,
                'voucher_number' => $a->voucher?->number,
                'amount_text' => $a->voucher
                    ? $this->money->money((float) $a->voucher->amount, $a->voucher->currency ?: $this->currency())
                    : null,
                'at' => $a->acted_at?->toIso8601String(),
            ])->values()->all(),
        ];
    }

    /** The "waiting on me" queue for review steps. */
    private function pendingFor(User $user): Collection
    {
        $queue = Voucher::query()->with(self::RELATIONS);
        $this->visibility->pendingFor($queue, $user);

        return $this->visibility->actionableOnly($queue->orderBy('submitted_at')->get(), $user);
    }

    /** @return Builder<Voucher> */
    private function visible(User $user): Builder
    {
        return $this->visibility->apply(Voucher::query(), $user);
    }

    /** @return Collection<int,Department> */
    private function scopedDepartments(User $user): Collection
    {
        return $user->headedDepartments()->orderBy('name')->get()
            ->merge($user->managedDepartments()->orderBy('name')->get())
            ->unique('id')
            ->values();
    }

    /** @return array{0:Carbon,1:Carbon} */
    private function month(): array
    {
        return [now()->startOfMonth(), now()->endOfMonth()];
    }

    private function format(float $amount): string
    {
        return $this->money->money($amount, $this->currency());
    }

    private function currency(): string
    {
        return $this->tenant->company()?->currency ?? 'TZS';
    }

    /**
     * By the company's own clock. The app runs on UTC, three hours behind
     * Tanzania, so reading the server's hour greeted afternoons as mornings.
     */
    private function greeting(): string
    {
        $hour = (int) now($this->tenant->company()?->timezone ?: 'Africa/Dar_es_Salaam')->format('G');

        return match (true) {
            $hour < 12 => 'Good morning',
            $hour < 17 => 'Good afternoon',
            default => 'Good evening',
        };
    }

    /** Last seven months of volume, for the dashboard bar chart. */
    private function monthlyVolume(): array
    {
        $rows = Voucher::query()
            ->selectRaw("DATE_FORMAT(voucher_date, '%Y-%m') as period, COUNT(*) as count, SUM(amount) as total")
            ->where('status', '!=', Voucher::STATUS_DRAFT)
            ->where('voucher_date', '>=', now()->subMonths(6)->startOfMonth())
            ->groupBy('period')
            ->orderBy('period')
            ->get()
            ->keyBy('period');

        $series = [];

        for ($i = 6; $i >= 0; $i--) {
            $month = now()->subMonths($i);
            $key = $month->format('Y-m');
            $row = $rows->get($key);

            $series[] = [
                'period' => $key,
                'label' => $month->format('M'),
                'count' => (int) ($row->count ?? 0),
                'total' => (float) ($row->total ?? 0),
                'is_current' => $i === 0,
            ];
        }

        return $series;
    }

    /**
     * Approved value per department — approved AND paid, since a voucher does
     * not stop being spend once the money has moved.
     *
     * @param  Builder<Voucher>  $scope  vouchers the caller may see
     * @param  bool  $includeEmpty  list departments with nothing approved yet
     */
    private function departmentSpend(Builder $scope, bool $includeEmpty): array
    {
        $totals = (clone $scope)
            ->whereNotNull('vouchers.approved_at')
            ->whereIn('vouchers.status', [Voucher::STATUS_APPROVED, Voucher::STATUS_PAID])
            ->selectRaw('vouchers.department_id, COUNT(vouchers.id) as count, COALESCE(SUM(vouchers.amount),0) as total')
            ->groupBy('vouchers.department_id')
            ->get()
            ->keyBy('department_id');

        $departments = Department::query()->orderBy('name')->get(['id', 'name']);

        $rows = $departments
            ->map(fn (Department $d) => [
                'id' => $d->id,
                'name' => $d->name,
                'count' => (int) ($totals->get($d->id)->count ?? 0),
                'total' => (float) ($totals->get($d->id)->total ?? 0),
            ])
            ->filter(fn (array $row) => $includeEmpty || $row['count'] > 0)
            ->sortByDesc('total')
            ->values();

        // A tenant with nothing approved yet is the common case on day one;
        // guard the share calculation against dividing by zero.
        $max = (float) $rows->max('total');
        $max = $max > 0 ? $max : 1.0;

        return $rows->map(fn (array $row) => $row + [
            'total_text' => $this->format($row['total']),
            'share' => round($row['total'] / $max * 100).'%',
        ])->all();
    }

    private function averageApproval(): ?string
    {
        $hours = Voucher::query()
            ->whereNotNull('submitted_at')
            ->whereNotNull('approved_at')
            ->selectRaw('AVG(TIMESTAMPDIFF(HOUR, submitted_at, approved_at)) as avg_hours')
            ->value('avg_hours');

        if ($hours === null) {
            return null;
        }

        $hours = (float) $hours;

        return $hours < 24
            ? round($hours, 1).' hours'
            : round($hours / 24, 1).' days';
    }
}
