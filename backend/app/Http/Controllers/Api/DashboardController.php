<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\VoucherResource;
use App\Models\Company;
use App\Models\Department;
use App\Models\Invoice;
use App\Models\User;
use App\Models\Voucher;
use App\Services\AmountFormatter;
use App\Services\VoucherVisibility;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Role-shaped dashboards. Each role is handed only figures it is entitled to see —
 * an employee's totals are computed from their own vouchers alone.
 */
class DashboardController extends Controller
{
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

        $inWorkflow = (clone $mine)->where('status', Voucher::STATUS_IN_REVIEW)->count();
        $approved = (clone $mine)->where('status', Voucher::STATUS_APPROVED)->count();
        $total = (float) (clone $mine)->sum('amount');

        $recent = Voucher::with(['requester', 'department', 'voucherType', 'workflow.steps'])
            ->where('requester_id', $user->id)
            ->latest('id')->limit(6)->get();

        return [
            'headline' => $inWorkflow > 0
                ? $this->plural($inWorkflow).' in the approval workflow'
                : 'Create a voucher',
            'sub' => 'You see only your own vouchers.'.($this->medianTurnaround($user) ? ' Your median turnaround is '.$this->medianTurnaround($user).'.' : ''),
            'stats' => [
                $this->stat('My vouchers', (string) (clone $mine)->count(), 'all time'),
                $this->stat('In the workflow', (string) $inWorkflow, 'with an approver'),
                $this->stat('Approved', (string) $approved, 'paid or scheduled'),
                $this->stat('Total requested', $this->money->money($total, $this->currency()), 'all time'),
            ],
            'recent' => VoucherResource::collection($recent),
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

        $signOnly = $pending->every(fn (Voucher $v) => ! ($v->currentStep()?->can_approve));

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
        ];
    }

    /* ---------------------------------------------------------------- admin */

    private function admin(Request $request): array
    {
        $all = Voucher::query();

        $pending = (clone $all)->where('status', Voucher::STATUS_IN_REVIEW)->count();
        $approved = (clone $all)->where('status', Voucher::STATUS_APPROVED)->count();
        $rejected = (clone $all)->where('status', Voucher::STATUS_REJECTED)->count();
        $total = (clone $all)->count();

        $thisMonth = (float) Voucher::whereBetween('voucher_date', [now()->startOfMonth(), now()->endOfMonth()])->sum('amount');
        $lastMonth = (float) Voucher::whereBetween('voucher_date', [
            now()->subMonthNoOverflow()->startOfMonth(), now()->subMonthNoOverflow()->endOfMonth(),
        ])->sum('amount');

        return [
            'headline' => $pending > 0 ? $this->plural($pending).' in the approval workflow' : 'Everything is up to date',
            'sub' => $total > 0
                ? round($approved / max($total, 1) * 100).'% of vouchers have been approved.'
                : 'No vouchers have been created yet.',
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
            'recent' => VoucherResource::collection(
                Voucher::with(['requester', 'department', 'voucherType', 'workflow.steps'])->latest('id')->limit(8)->get()
            ),
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
        $max = null;

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

        $max = (float) ($rows->max('total') ?: 1);

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
