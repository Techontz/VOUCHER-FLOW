<?php

namespace App\Policies;

use App\Models\User;
use App\Models\Workflow;

/**
 * Who may reshape the route a voucher travels.
 *
 * This is an unusually powerful permission: a workflow defines who signs, who
 * approves and who may release money, so being able to edit one is being able
 * to grant yourself all three. It belongs to administrators alone, and the
 * tenant scope keeps even them inside their own company.
 */
class WorkflowPolicy
{
    public function viewAny(User $user): bool
    {
        // Everyone may read the route their own vouchers will travel; the
        // timeline on a voucher is built from it.
        return $user->company_id !== null || $user->isSuperAdmin();
    }

    public function view(User $user, Workflow $workflow): bool
    {
        return $user->isSuperAdmin() || $user->company_id === $workflow->company_id;
    }

    public function create(User $user): bool
    {
        return $user->isAdmin();
    }

    public function update(User $user, Workflow $workflow): bool
    {
        return $user->isAdmin() && $this->view($user, $workflow);
    }

    public function delete(User $user, Workflow $workflow): bool
    {
        return $this->update($user, $workflow);
    }
}
