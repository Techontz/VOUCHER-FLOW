<?php

namespace App\Policies;

use App\Models\User;
use App\Models\Voucher;
use App\Services\VoucherVisibility;
use App\Services\WorkflowEngine;

/**
 * Every question the API asks about a voucher, answered in one place.
 *
 * The rules themselves already lived in VoucherVisibility (who may see a row)
 * and WorkflowEngine (what the current step permits). What was missing was a
 * single door they were asked through: each controller had its own private
 * authorizeView(), which is four copies of a security decision and four places
 * for one of them to drift.
 *
 * Nothing here re-implements a rule. The policy delegates, so the API, a future
 * console command and a queued job all get the same answer.
 */
class VoucherPolicy
{
    public function __construct(
        private readonly VoucherVisibility $visibility,
        private readonly WorkflowEngine $engine,
    ) {}

    /**
     * Row-level visibility, on top of the tenant scope that has already run.
     *
     * Deliberately re-queried rather than inspected in PHP: the visibility rules
     * are expressed as SQL, and evaluating them twice in two languages is how
     * the two versions come to disagree.
     */
    public function view(User $user, Voucher $voucher): bool
    {
        return $this->visibility
            ->apply(Voucher::query()->whereKey($voucher->id), $user)
            ->exists();
    }

    public function update(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'edit');
    }

    public function delete(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'delete');
    }

    public function submit(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'submit');
    }

    public function sign(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'sign');
    }

    public function submitSigned(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'submit_signed');
    }

    public function approve(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'approve');
    }

    public function reject(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'reject');
    }

    public function requestChanges(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'request_changes');
    }

    public function cancel(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'cancel');
    }

    /** Releasing money — the highest-value action in the system. */
    public function pay(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'pay');
    }

    public function print(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'print');
    }

    public function download(User $user, Voucher $voucher): bool
    {
        return $this->can($user, $voucher, 'download');
    }

    public function comment(User $user, Voucher $voucher): bool
    {
        return $this->view($user, $voucher);
    }

    /**
     * A workflow action is permitted only if the caller may see the voucher AND
     * the step they are standing on grants it. Both halves, always — a visible
     * voucher is not an actionable one.
     */
    private function can(User $user, Voucher $voucher, string $action): bool
    {
        return $this->view($user, $voucher)
            && ($this->engine->availableActions($user, $voucher)[$action] ?? false);
    }
}
