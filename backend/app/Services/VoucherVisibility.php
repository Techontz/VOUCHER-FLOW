<?php

namespace App\Services;

use App\Models\User;
use App\Models\Voucher;
use Illuminate\Database\Eloquent\Builder;

/**
 * Row-level visibility on top of tenant isolation.
 *
 * Tenant isolation already guarantees a user never sees another company's data.
 * This narrows further, per the product rule that an employee sees only their own
 * vouchers and an approver sees only what their workflow actually routes to them.
 */
class VoucherVisibility
{
    public function __construct(private readonly WorkflowEngine $engine) {}

    public function apply(Builder $query, User $user): Builder
    {
        if ($user->isSuperAdmin() || $user->isCompanyAdmin()) {
            return $query;
        }

        // Employees see exactly their own record — nothing else, at any status.
        if (! $user->isApprover()) {
            return $query->where('vouchers.requester_id', $user->id);
        }

        return $query->where(function (Builder $q) use ($user) {
            // Their own requests.
            $q->where('vouchers.requester_id', $user->id);

            // Departments they head or manage — but never other people's drafts.
            $scoped = $user->headedDepartments()->pluck('id')
                ->merge($user->managedDepartments()->pluck('id'))
                ->unique()
                ->all();

            if ($scoped) {
                $q->orWhere(fn (Builder $d) => $d
                    ->whereIn('vouchers.department_id', $scoped)
                    ->where('vouchers.status', '!=', Voucher::STATUS_DRAFT));
            }

            // Steps that name them personally.
            $q->orWhereExists(function ($sub) use ($user) {
                $sub->selectRaw('1')
                    ->from('workflow_steps')
                    ->whereColumn('workflow_steps.workflow_id', 'vouchers.workflow_id')
                    ->where('workflow_steps.assigned_user_id', $user->id);
            });

            // Roles that are not department-bound act for the whole company, so a
            // bare role match is enough for them — and only for them. A role match
            // alone must never widen an HOD or manager beyond their departments,
            // since an unassigned "hod" step exists on every voucher.
            if (in_array($user->role, [User::ROLE_FINANCE, User::ROLE_DIRECTOR], true)) {
                $q->orWhereExists(function ($sub) use ($user) {
                    $sub->selectRaw('1')
                        ->from('workflow_steps')
                        ->whereColumn('workflow_steps.workflow_id', 'vouchers.workflow_id')
                        ->whereNull('workflow_steps.assigned_user_id')
                        ->where('workflow_steps.role', $user->role);
                });
            }

            // Anything they have already acted on stays visible to them.
            $q->orWhereExists(function ($sub) use ($user) {
                $sub->selectRaw('1')
                    ->from('voucher_approvals')
                    ->whereColumn('voucher_approvals.voucher_id', 'vouchers.id')
                    ->where('voucher_approvals.actor_id', $user->id);
            });
        })->where(function (Builder $q) use ($user) {
            // Whatever matched above, a draft belonging to someone else stays hidden.
            $q->where('vouchers.status', '!=', Voucher::STATUS_DRAFT)
                ->orWhere('vouchers.requester_id', $user->id);
        });
    }

    /** The "awaiting me" queue: vouchers parked on a step this user may act on. */
    public function pendingFor(Builder $query, User $user): Builder
    {
        $query->where('vouchers.status', Voucher::STATUS_IN_REVIEW);

        if ($user->isSuperAdmin() || $user->isCompanyAdmin()) {
            return $query;
        }

        return $query->whereExists(function ($sub) use ($user) {
            $sub->selectRaw('1')
                ->from('workflow_steps')
                ->whereColumn('workflow_steps.workflow_id', 'vouchers.workflow_id')
                ->whereColumn('workflow_steps.position', 'vouchers.current_step_position')
                ->where(function ($w) use ($user) {
                    $w->where('workflow_steps.assigned_user_id', $user->id)
                        ->orWhere(function ($r) use ($user) {
                            $r->whereNull('workflow_steps.assigned_user_id')
                                ->where('workflow_steps.role', $user->role);
                        });
                });
        })->where(function (Builder $q) use ($user) {
            // Role-matched steps still respect department headship where it applies.
            $headed = $user->headedDepartments()->pluck('id')
                ->merge($user->managedDepartments()->pluck('id'))
                ->unique()
                ->all();

            $q->whereExists(function ($sub) use ($user) {
                $sub->selectRaw('1')
                    ->from('workflow_steps')
                    ->whereColumn('workflow_steps.workflow_id', 'vouchers.workflow_id')
                    ->whereColumn('workflow_steps.position', 'vouchers.current_step_position')
                    ->where('workflow_steps.assigned_user_id', $user->id);
            });

            if ($headed) {
                $q->orWhereIn('vouchers.department_id', $headed);
            }

            // Roles that are not department-bound (finance, director) see all.
            if (in_array($user->role, [User::ROLE_FINANCE, User::ROLE_DIRECTOR], true)) {
                $q->orWhereNotNull('vouchers.id');
            }
        });
    }

    /** Filters a final result set to those the user may actually act on now. */
    public function actionableOnly($vouchers, User $user)
    {
        return $vouchers->filter(function (Voucher $voucher) use ($user) {
            $step = $this->engine->stepAt($voucher, $voucher->current_step_position);

            return $step && $this->engine->canActOnStep($user, $voucher, $step);
        })->values();
    }
}
