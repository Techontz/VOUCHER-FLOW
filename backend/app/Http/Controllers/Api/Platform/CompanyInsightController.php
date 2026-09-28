<?php

namespace App\Http\Controllers\Api\Platform;

use App\Http\Controllers\Api\WorkflowController;
use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Http\Resources\VoucherResource;
use App\Http\Resources\WorkflowResource;
use App\Models\Company;
use App\Models\Department;
use App\Models\User;
use App\Models\Voucher;
use App\Models\Workflow;
use App\Services\WorkflowEngine;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/**
 * Read-only views into one tenant for the platform super admin: its people,
 * departments, approval route, vouchers and money.
 *
 * Every query runs inside TenantContext::forCompany($company), so the
 * tenant's own global scopes decide what is visible — exactly what the
 * company's administrator would see, never another company's rows. Nothing
 * here changes data.
 */
class CompanyInsightController extends Controller
{
    public function __construct(
        private readonly TenantContext $tenant,
        private readonly WorkflowEngine $engine,
    ) {}

    /** Headline figures: vouchers by status and stage, money, people. */
    public function overview(Company $company)
    {
        return response()->json(['data' => $this->tenant->forCompany($company, function () use ($company) {
            $byStatus = Voucher::query()
                ->selectRaw('status, COUNT(*) as count, COALESCE(SUM(amount), 0) as value')
                ->groupBy('status')
                ->get()
                ->keyBy('status');

            $count = fn (string $s) => (int) ($byStatus[$s]->count ?? 0);
            $value = fn (string $s) => (float) ($byStatus[$s]->value ?? 0);

            // Vouchers under review, grouped by the step they are waiting at.
            $stages = Voucher::query()
                ->with('workflow.steps')
                ->where('status', Voucher::STATUS_IN_REVIEW)
                ->get()
                ->groupBy(function (Voucher $v) {
                    $step = $this->engine->stepAt($v, $v->current_step_position);

                    return $step ? $step->position.'|'.$step->name.'|'.$step->role : '0|Unassigned|';
                })
                ->map(function ($group, $key) {
                    [$position, $name, $role] = explode('|', $key, 3);

                    return [
                        'position' => (int) $position,
                        'name' => $name,
                        'role' => $role ?: null,
                        'count' => $group->count(),
                        'value' => (float) $group->sum('amount'),
                    ];
                })
                ->sortBy('position')
                ->values();

            $recentPayments = Voucher::query()
                ->with(['paidBy', 'department', 'requester'])
                ->where('status', Voucher::STATUS_PAID)
                ->orderByDesc('paid_at')
                ->limit(10)
                ->get()
                ->map(fn (Voucher $v) => [
                    'id' => $v->id,
                    'number' => $v->number,
                    'payee' => $v->payee,
                    'purpose' => $v->purpose,
                    'amount' => (float) $v->amount,
                    'currency' => $v->currency,
                    'kind' => $v->kind,
                    'payment_method' => $v->payment_method,
                    'payment_reference' => $v->payment_reference,
                    'payment_date' => $v->payment_date?->toDateString(),
                    'paid_at' => $v->paid_at?->toIso8601String(),
                    'paid_by' => $v->paidBy?->name,
                    'department' => $v->department?->name,
                ]);

            $users = User::forTenant($company->id);
            $since = Carbon::now()->startOfMonth()->subMonths(5);
            $monthly = Voucher::query()
                ->whereNotNull('submitted_at')
                ->where('submitted_at', '>=', $since)
                ->get(['submitted_at', 'amount'])
                ->groupBy(fn (Voucher $v) => $v->submitted_at->format('Y-m'));

            return [
                'vouchers' => [
                    'total' => $byStatus->sum('count'),
                    'draft' => $count(Voucher::STATUS_DRAFT),
                    'in_review' => $count(Voucher::STATUS_IN_REVIEW),
                    'changes_requested' => $count(Voucher::STATUS_CHANGES_REQUESTED),
                    'approved' => $count(Voucher::STATUS_APPROVED),
                    'rejected' => $count(Voucher::STATUS_REJECTED),
                    'cancelled' => $count(Voucher::STATUS_CANCELLED),
                    'paid' => $count(Voucher::STATUS_PAID),
                ],
                'values' => [
                    'total' => (float) $byStatus->sum('value'),
                    'in_review' => $value(Voucher::STATUS_IN_REVIEW),
                    'approved_unpaid' => $value(Voucher::STATUS_APPROVED),
                    'approved_including_paid' => $value(Voucher::STATUS_APPROVED) + $value(Voucher::STATUS_PAID),
                    'paid' => $value(Voucher::STATUS_PAID),
                    'rejected' => $value(Voucher::STATUS_REJECTED),
                ],
                'stages' => $stages,
                'payments' => [
                    'paid_count' => $count(Voucher::STATUS_PAID),
                    'paid_value' => $value(Voucher::STATUS_PAID),
                    'pending_count' => $count(Voucher::STATUS_APPROVED),
                    'pending_value' => $value(Voucher::STATUS_APPROVED),
                    'recent' => $recentPayments,
                ],
                'people' => [
                    'total' => (clone $users)->count(),
                    'active' => (clone $users)->where('status', 'active')->count(),
                    'by_role' => (clone $users)->selectRaw('role, COUNT(*) as count')->groupBy('role')->pluck('count', 'role'),
                    'departments' => Department::count(),
                ],
                'monthly' => collect(range(0, 5))->map(function (int $i) use ($since, $monthly) {
                    $key = $since->copy()->addMonths($i)->format('Y-m');
                    $rows = $monthly->get($key, collect());

                    return ['month' => $key, 'count' => $rows->count(), 'value' => (float) $rows->sum('amount')];
                }),
                'currency' => $company->currency ?? 'TZS',
            ];
        })]);
    }

    /** The company's people. */
    public function users(Request $request, Company $company)
    {
        $request->validate([
            'q' => ['nullable', 'string', 'max:120'],
            'role' => ['nullable', 'string', 'max:40'],
            'status' => ['nullable', 'string', 'max:20'],
            'department_id' => ['nullable', 'integer'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);

        return $this->tenant->forCompany($company, fn () => UserResource::collection(
            User::query()
                ->forTenant($company->id)
                ->with('department')
                ->withCount('vouchers')
                ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                    ->where('name', 'like', "%{$v}%")
                    ->orWhere('email', 'like', "%{$v}%")
                    ->orWhere('employee_code', 'like', "%{$v}%")))
                ->when($request->query('role'), fn ($q, $v) => $q->where('role', $v))
                ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
                ->when($request->query('department_id'), fn ($q, $v) => $q->where('department_id', $v))
                ->orderBy('name')
                ->paginate((int) $request->query('per_page', 25))
                ->withQueryString()
        // Serialised inside the tenant scope, not after it has been restored.
        )->response($request));
    }

    /** Departments with their heads, headcount and all-time voucher value. */
    public function departments(Company $company)
    {
        return response()->json(['data' => $this->tenant->forCompany($company, function () {
            $value = Voucher::query()
                ->whereIn('status', [Voucher::STATUS_APPROVED, Voucher::STATUS_PAID])
                ->selectRaw('department_id, SUM(amount) as total')
                ->groupBy('department_id')
                ->pluck('total', 'department_id');

            return Department::with(['hod', 'manager'])
                ->withCount(['users', 'vouchers'])
                ->orderBy('name')
                ->get()
                ->map(fn (Department $d) => [
                    'id' => $d->id,
                    'name' => $d->name,
                    'code' => $d->code,
                    'cost_centre' => $d->cost_centre,
                    'is_active' => (bool) $d->is_active,
                    'hod' => $d->hod ? ['id' => $d->hod->id, 'name' => $d->hod->name, 'email' => $d->hod->email] : null,
                    'manager' => $d->manager ? ['id' => $d->manager->id, 'name' => $d->manager->name, 'email' => $d->manager->email] : null,
                    'users_count' => $d->users_count,
                    'vouchers_count' => $d->vouchers_count,
                    'approved_value' => (float) ($value[$d->id] ?? 0),
                ]);
        })]);
    }

    /** The approval workflows, and who each step resolves to per department. */
    public function workflows(Request $request, Company $company)
    {
        return response()->json(['data' => $this->tenant->forCompany($company, function () use ($request) {
            $workflows = Workflow::with(['steps.assignedUser', 'voucherType'])
                ->withCount('vouchers')
                ->orderByDesc('is_default')
                ->orderBy('name')
                ->get();

            $default = $workflows->firstWhere('is_default', true) ?? $workflows->first();

            // The same resolution the company admin's routing matrix uses.
            $routing = $default
                ? app(WorkflowController::class)->routing($request, $default)->getData(true)['data']
                : null;

            return [
                'workflows' => WorkflowResource::collection($workflows)->resolve($request),
                'default_id' => $default?->id,
                'routing' => $routing,
            ];
        })]);
    }

    /** The company's vouchers, with the register's filters. */
    public function vouchers(Request $request, Company $company)
    {
        $request->validate([
            'q' => ['nullable', 'string', 'max:120'],
            'status' => ['nullable', 'string', 'max:40'],
            'department_id' => ['nullable', 'integer'],
            'requester_id' => ['nullable', 'integer'],
            'voucher_type_id' => ['nullable', 'integer'],
            'kind' => ['nullable', Rule::in(Voucher::KINDS)],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
            'min_amount' => ['nullable', 'numeric'],
            'max_amount' => ['nullable', 'numeric'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);

        return $this->tenant->forCompany($company, function () use ($request, $company) {
            $status = match ($request->query('status')) {
                'awaiting_payment' => Voucher::STATUS_APPROVED,
                default => $request->query('status'),
            };

            $query = Voucher::query()
                ->with(['requester', 'department', 'voucherType', 'paidBy', 'workflow.steps'])
                ->status($status)
                ->search($request->query('q'))
                ->when(in_array($request->query('kind'), Voucher::KINDS, true), fn ($q) => $q->where('kind', $request->query('kind')))
                ->when($request->query('department_id'), fn ($q, $v) => $q->where('department_id', $v))
                ->when($request->query('requester_id'), fn ($q, $v) => $q->where('requester_id', $v))
                ->when($request->query('voucher_type_id'), fn ($q, $v) => $q->where('voucher_type_id', $v))
                ->when($request->query('from'), fn ($q, $v) => $q->whereDate('voucher_date', '>=', $v))
                ->when($request->query('to'), fn ($q, $v) => $q->whereDate('voucher_date', '<=', $v))
                ->when($request->query('min_amount'), fn ($q, $v) => $q->where('amount', '>=', $v))
                ->when($request->query('max_amount'), fn ($q, $v) => $q->where('amount', '<=', $v));

            $page = (clone $query)
                ->orderByDesc('voucher_date')->orderByDesc('id')
                ->paginate((int) $request->query('per_page', 20))
                ->withQueryString();

            return VoucherResource::collection($page)->additional([
                'meta' => [
                    'total_amount' => (float) (clone $query)->sum('amount'),
                    'currency' => $company->currency ?? 'TZS',
                ],
            ])->response($request);
        });
    }
}
