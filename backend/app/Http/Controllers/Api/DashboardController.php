<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\VoucherResource;
use App\Models\Company;
use App\Models\Department;
use App\Models\Invoice;
use App\Models\User;
use App\Models\Voucher;
use App\Models\WorkflowStep;
use App\Services\AmountFormatter;
use App\Services\VoucherVisibility;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Role-shaped dashboards.
 *
 * A dashboard is an ACTION QUEUE, not a history page. It answers one question:
 * what is waiting on *you*, right now. The moment a user completes their step
 * the voucher leaves their queue and appears on whoever is next — so an empty
 * dashboard means the work is genuinely clear, not that nothing has happened.
 *
 * Anything already dealt with is found through Reports, subject to the same
 * permissions. That is deliberate: a queue that also lists finished work stops
 * being a queue, and people stop trusting it to tell them what to do.
 *
 * Each role is additionally handed only figures it is entitled to see — an
 * employee's totals are computed from their own vouchers alone.
 */
class DashboardController extends Controller
{
    /** How long a voucher may sit on one step before an admin should look. */
    private const STALL_DAYS = 3;

    public function __construct(
        private readonly VoucherVisibility $visibility,
        private readonly AmountFormatter $money,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request)
    {
        $user = $request->user();

        return response()->json([
            'role' => $user->role,
            'greeting' => $this->greeting(),
            'data' => match (true) {
                $user->isSuperAdmin() && ! $this->tenant->hasTenant() => $this->platform(),
                $user->isCompanyAdmin() || $user->isSuperAdmin() => $this->admin($request),
                // Checked before the general approver branch: a cashier holds no
                // review step, so "awaiting me" for them means approved-and-unpaid.
                $this->paysMoney($user) => $this->cashier($request),
                $user->isApprover() => $this->approver($request),
                default => $this->employee($request),
            },
        ]);
    }

    /* ------------------------------------------------------------- employee */

    private function employee(Request $request): array
    {
        $user = $request->user();
        $mine = Voucher::where('requester_id', $user->id);

        // The employee's own move: finish a draft, or answer a request for
        // changes. A voucher they have submitted is with someone else and is
        // deliberately not here — they can follow it in Reports.
        $queue = Voucher::with(['requester', 'department', 'voucherType', 'workflow.steps'])
            ->where('requester_id', $user->id)
            ->whereIn('status', [Voucher::STATUS_DRAFT, Voucher::STATUS_CHANGES_REQUESTED])
            ->orderByDesc('voucher_date')->orderByDesc('id')
            ->get();

        $inFlight = (clone $mine)->whereIn('status', [Voucher::STATUS_IN_REVIEW, Voucher::STATUS_APPROVED])->count();
        $inFlightValue = (float) (clone $mine)->whereIn('status', [Voucher::STATUS_IN_REVIEW, Voucher::STATUS_APPROVED])->sum('amount');
        $paid = (clone $mine)->where('status', Voucher::STATUS_PAID)->count();
        $paidValue = (float) (clone $mine)->where('status', Voucher::STATUS_PAID)->sum('amount');
        $thisYear = (clone $mine)->whereYear('voucher_date', now()->year);

        return [
            'headline' => $queue->count() > 0
                ? $this->plural($queue->count()).' need your attention'
                : 'Nothing needs your attention',
            'sub' => $queue->count() > 0
                ? 'Finish these and they move on for review.'
                : 'Everything you have raised is with someone else. Reports has your history.',
            'stats' => [
                $this->stat('On you', (string) $queue->count(), 'drafts and returns'),
                $this->stat('With an approver', (string) $inFlight, $this->money->money($inFlightValue, $this->currency())),
                $this->stat('Paid', (string) $paid, $this->money->money($paidValue, $this->currency())),
                $this->stat('Raised this year', (string) $thisYear->count(),
                    $this->money->money((float) (clone $thisYear)->sum('amount'), $this->currency())),
            ],
            'queue' => VoucherResource::collection($queue),
            'queue_total_text' => $this->money->money((float) $queue->sum('amount'), $this->currency()),
        ];
    }

    /* ------------------------------------------------------------- approver */

    private function approver(Request $request): array
    {
        $user = $request->user();

        $queue = Voucher::query()->with(['requester', 'department', 'voucherType', 'workflow.steps']);
        $this->visibility->pendingFor($queue, $user);
        $pending = $this->visibility->actionableOnly($queue->orderBy('submitted_at')->get(), $user);

        $signedThisMonth = Voucher::whereHas('approvals', fn ($q) => $q
            ->where('actor_id', $user->id)
            ->whereIn('action', ['signed', 'approved'])
            ->whereBetween('acted_at', [now()->startOfMonth(), now()->endOfMonth()]))->count();

        $returned = Voucher::whereHas('approvals', fn ($q) => $q
            ->where('actor_id', $user->id)
            ->whereIn('action', ['changes_requested', 'rejected']))->count();

        $departments = $user->headedDepartments()->pluck('id')
            ->merge($user->managedDepartments()->pluck('id'))->unique();

        $deptValue = $departments->isNotEmpty()
            ? (float) Voucher::whereIn('department_id', $departments)
                ->where('status', Voucher::STATUS_APPROVED)
                ->whereBetween('voucher_date', [now()->firstOfQuarter(), now()->lastOfQuarter()])
                ->sum('amount')
            : 0.0;

        // Derived from the steps this user actually holds, not from whatever
        // happens to be in the queue: an HOD whose queue is momentarily empty
        // still signs only, and the wording must not flip to "decision" the
        // instant they clear it.
        $mySteps = WorkflowStep::query()
            ->whereHas('workflow', fn ($w) => $w->where('company_id', $user->company_id))
            ->where(fn ($q) => $q->where('assigned_user_id', $user->id)
                ->orWhere(fn ($r) => $r->whereNull('assigned_user_id')->where('role', $user->role)))
            ->get();

        $signOnly = $mySteps->isNotEmpty() && $mySteps->every(fn (WorkflowStep $st) => ! $st->can_approve);

        return [
            'headline' => $pending->count() > 0
                ? $this->plural($pending->count()).' '.($signOnly ? 'awaiting your signature' : 'awaiting your decision')
                : 'Nothing awaiting you',
            'sub' => $signOnly
                ? 'Your step signs only — the approval decision sits with a later step.'
                : 'Each one has reached your step in the approval workflow.',
            'stats' => [
                $this->stat('Awaiting you', (string) $pending->count(), 'right now'),
                $this->stat('Actioned this month', (string) $signedThisMonth, 'signed or approved'),
                $this->stat('Returned for changes', (string) $returned, 'all time'),
                $this->stat('Department value', $this->money->money($deptValue, $this->currency()), 'this quarter'),
            ],
            'queue' => VoucherResource::collection($pending),
            'queue_total_text' => $this->money->money((float) $pending->sum('amount'), $this->currency()),
        ];
    }

    /* -------------------------------------------------------------- cashier */

    /**
     * Whoever the workflow entrusts with releasing money. Their queue is what
     * has been approved and not yet paid — and it empties as they pay.
     */
    private function cashier(Request $request): array
    {
        $user = $request->user();
        $engine = app(\App\Services\WorkflowEngine::class);

        $query = Voucher::with(['requester', 'department', 'voucherType', 'workflow.steps'])
            ->awaitingPayment();
        $this->visibility->apply($query, $user);

        $queue = $query->orderBy('approved_at')->get()
            ->filter(fn (Voucher $v) => $engine->canPay($user, $v))
            ->values();

        $bank = $queue->where('kind', Voucher::KIND_BANK);
        $cash = $queue->where('kind', Voucher::KIND_CASH);

        $paidThisMonth = Voucher::where('paid_by_id', $user->id)
            ->whereBetween('paid_at', [now()->startOfMonth(), now()->endOfMonth()]);

        return [
            'headline' => $queue->count() > 0
                ? $this->plural($queue->count()).' to pay'
                : 'Nothing to pay',
            'sub' => $queue->count() > 0
                ? 'Approved and waiting on the money. Recording payment closes each one.'
                : 'Every approved voucher has been settled.',
            'stats' => [
                $this->stat('To pay', (string) $queue->count(), $this->money->money((float) $queue->sum('amount'), $this->currency())),
                $this->stat('Bank transfers', (string) $bank->count(), $this->money->money((float) $bank->sum('amount'), $this->currency())),
                $this->stat('Cash', (string) $cash->count(), $this->money->money((float) $cash->sum('amount'), $this->currency())),
                $this->stat('Released this month', (string) (clone $paidThisMonth)->count(),
                    $this->money->money((float) (clone $paidThisMonth)->sum('amount'), $this->currency())),
            ],
            'queue' => VoucherResource::collection($queue),
            'queue_total_text' => $this->money->money((float) $queue->sum('amount'), $this->currency()),
        ];
    }

    /** Whether any step in this tenant's workflows gives this user the money. */
    private function paysMoney(User $user): bool
    {
        if (! $user->company_id || $user->isAdmin()) {
            return false;
        }

        return WorkflowStep::query()
            ->where('can_pay', true)
            ->whereHas('workflow', fn ($w) => $w->where('company_id', $user->company_id))
            ->where(fn ($q) => $q->where('assigned_user_id', $user->id)
                ->orWhere(fn ($r) => $r->whereNull('assigned_user_id')->where('role', $user->role)))
            ->exists();
    }

    /* ---------------------------------------------------------------- admin */

    private function admin(Request $request): array
    {
        $all = Voucher::query();

        // An administrator's queue is not "everything that exists" — that is a
        // register, and they already have one. What actually needs them is what
        // has STOPPED: vouchers sitting on the same step long enough that
        // someone has to go and unblock them.
        $stalled = Voucher::with(['requester', 'department', 'voucherType', 'workflow.steps'])
            ->where('status', Voucher::STATUS_IN_REVIEW)
            ->where(fn ($q) => $q
                ->where('updated_at', '<=', now()->subDays(self::STALL_DAYS))
                ->orWhere(fn ($r) => $r->whereNull('updated_at')
                    ->where('submitted_at', '<=', now()->subDays(self::STALL_DAYS))))
            ->orderBy('updated_at')
            ->get();

        $pending = (clone $all)->where('status', Voucher::STATUS_IN_REVIEW)->count();
        $approved = (clone $all)->where('status', Voucher::STATUS_APPROVED)->count();
        $rejected = (clone $all)->where('status', Voucher::STATUS_REJECTED)->count();
        $total = (clone $all)->count();

        $thisMonth = (float) Voucher::whereBetween('voucher_date', [now()->startOfMonth(), now()->endOfMonth()])->sum('amount');
        $lastMonth = (float) Voucher::whereBetween('voucher_date', [
            now()->subMonthNoOverflow()->startOfMonth(), now()->subMonthNoOverflow()->endOfMonth(),
        ])->sum('amount');

        return [
            'headline' => $stalled->count() > 0
                ? $this->plural($stalled->count()).' have stalled'
                : 'Nothing has stalled',
            'sub' => $stalled->count() > 0
                ? 'Sitting on the same step for '.self::STALL_DAYS.' days or more.'
                : ($pending > 0
                    ? $this->plural($pending).' are moving through the workflow normally.'
                    : 'No vouchers are currently in the workflow.'),
            'stats' => [
                $this->stat('Total vouchers', (string) $total, 'all time'),
                $this->stat('Pending approval', (string) $pending, 'in the workflow'),
                $this->stat('Approved', (string) $approved, $total ? round($approved / max($total, 1) * 100).'% of all' : '—'),
                $this->stat('Rejected', (string) $rejected, $total ? round($rejected / max($total, 1) * 100).'% of all' : '—'),
                $this->stat('Value this month', $this->money->money($thisMonth, $this->currency()),
                    $lastMonth > 0 ? 'vs '.$this->money->money($lastMonth, $this->currency()).' last month' : 'no prior month'),
                $this->stat('Avg. approval time', $this->averageApproval() ?? '—', 'submission to decision'),
            ],
            'volume' => $this->monthlyVolume(),
            'by_department' => $this->departmentSpend(),
            'queue' => VoucherResource::collection($stalled),
            'queue_total_text' => $this->money->money((float) $stalled->sum('amount'), $this->currency()),
        ];
    }

    /* ------------------------------------------------------------- platform */

    private function platform(): array
    {
        $companies = Company::count();
        $active = Company::where('status', 'active')->count();
        $trial = Company::where('status', 'trial')->count();
        $pastDue = Company::whereIn('status', ['past_due', 'suspended'])->count();

        $users = User::whereNotNull('company_id')->count();
        $vouchers = Voucher::query()->withoutGlobalScopes()->count();

        $revenue = (float) Invoice::query()->withoutGlobalScopes()
            ->where('status', 'paid')
            ->whereBetween('paid_at', [now()->startOfMonth(), now()->endOfMonth()])
            ->sum('total');

        $runRate = (float) Invoice::query()->withoutGlobalScopes()
            ->where('status', 'paid')
            ->where('paid_at', '>=', now()->subYear())
            ->sum('total');

        return [
            'headline' => "{$companies} companies · ".number_format($users).' users · '.number_format($vouchers).' vouchers',
            'sub' => 'Monthly revenue '.$this->money->money($revenue, 'TZS').($pastDue ? " · {$pastDue} accounts need attention." : '.'),
            'stats' => [
                $this->stat('Total companies', (string) $companies, "{$active} active · {$trial} trial · {$pastDue} at risk"),
                $this->stat('Monthly revenue', $this->money->money($revenue, 'TZS'), 'invoices paid this month'),
                $this->stat('Trailing 12m revenue', $this->money->money($runRate, 'TZS'), 'collected'),
                $this->stat('Total users', number_format($users), 'across all companies'),
                $this->stat('Total vouchers', number_format($vouchers), 'platform-wide'),
                $this->stat('Pending / approved / rejected',
                    Voucher::query()->withoutGlobalScopes()->where('status', Voucher::STATUS_IN_REVIEW)->count().' / '.
                    Voucher::query()->withoutGlobalScopes()->where('status', Voucher::STATUS_APPROVED)->count().' / '.
                    Voucher::query()->withoutGlobalScopes()->where('status', Voucher::STATUS_REJECTED)->count(),
                    'platform-wide'),
            ],
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

    /* -------------------------------------------------------------- helpers */

    private function stat(string $label, string $value, string $sub): array
    {
        return ['label' => $label, 'value' => $value, 'sub' => $sub];
    }

    private function plural(int $n): string
    {
        return $n.' '.($n === 1 ? 'voucher' : 'vouchers');
    }

    private function currency(): string
    {
        return $this->tenant->company()?->currency ?? 'TZS';
    }

    private function greeting(): string
    {
        $hour = (int) now()->format('G');

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

    private function departmentSpend(): array
    {
        $rows = Department::query()
            ->leftJoin('vouchers', function ($join) {
                $join->on('vouchers.department_id', '=', 'departments.id')
                    ->where('vouchers.status', '=', Voucher::STATUS_APPROVED)
                    ->whereNull('vouchers.deleted_at');
            })
            ->selectRaw('departments.id, departments.name, COUNT(vouchers.id) as count, COALESCE(SUM(vouchers.amount),0) as total')
            ->groupBy('departments.id', 'departments.name')
            ->orderByDesc('total')
            ->get();

        // SUM() comes back as the string "0.00", which is truthy — so the
        // obvious `?: 1` guard does not fire and the share calculation divides
        // by zero. A tenant with nothing approved yet is the common case on day
        // one, and its administrator's dashboard should not 500.
        $max = (float) $rows->max('total');
        $max = $max > 0 ? $max : 1.0;

        return $rows->map(fn ($row) => [
            'id' => $row->id,
            'name' => $row->name,
            'count' => (int) $row->count,
            'total' => (float) $row->total,
            'share' => round((float) $row->total / $max * 100).'%',
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

    private function medianTurnaround(User $user): ?string
    {
        $hours = Voucher::where('requester_id', $user->id)
            ->whereNotNull('submitted_at')->whereNotNull('approved_at')
            ->selectRaw('AVG(TIMESTAMPDIFF(HOUR, submitted_at, approved_at)) as avg_hours')
            ->value('avg_hours');

        if ($hours === null) {
            return null;
        }

        return (float) $hours < 24 ? round((float) $hours, 1).' hours' : round((float) $hours / 24, 1).' days';
    }
}
