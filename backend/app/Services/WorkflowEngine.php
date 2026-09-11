<?php

namespace App\Services;

use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherApproval;
use App\Models\VoucherType;
use App\Models\Workflow;
use App\Models\WorkflowStep;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Drives a voucher through its company's own approval route.
 *
 * Nothing here assumes an HOD-then-Manager shape. What a participant may do at a
 * step comes entirely from that step's stored capability flags, so one tenant can
 * run "HOD signs, Manager approves" while another runs a four-step route with
 * Finance in the middle, or a single approver.
 */
class WorkflowEngine
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly Notifier $notifier,
    ) {}

    /* ---------------------------------------------------------------- routing */

    /** The workflow that governs a voucher type: type-specific first, else default. */
    public function resolveWorkflow(VoucherType $type): ?Workflow
    {
        return Workflow::query()
            ->where('is_active', true)
            ->where(fn ($q) => $q->where('voucher_type_id', $type->id)->orWhereNull('voucher_type_id'))
            ->orderByRaw('voucher_type_id IS NULL')   // type-specific wins
            ->orderByDesc('is_default')
            ->with('steps')
            ->first();
    }

    /**
     * Steps that apply to this voucher, after amount-threshold filtering.
     * The request step (position 1) always applies.
     */
    public function applicableSteps(Voucher $voucher): Collection
    {
        $workflow = $voucher->relationLoaded('workflow') ? $voucher->workflow : $voucher->workflow()->with('steps')->first();

        if (! $workflow) {
            return new Collection;
        }

        $amount = (float) $voucher->amount;

        return $workflow->steps
            ->filter(fn (WorkflowStep $step) => $step->isRequestStep() || $step->appliesToAmount($amount))
            ->values();
    }

    /**
     * The approval chain: everything between the request and the money.
     *
     * A pay-only step is deliberately not in here. Advancing into it would park
     * the voucher in "under review" when the reviewing is finished — what is
     * actually outstanding at that point is a payment, and the status should say
     * so. Approval completes the chain; `pay()` acts on the approved voucher.
     */
    public function approvalSteps(Voucher $voucher): Collection
    {
        return $this->applicableSteps($voucher)
            ->reject(fn (WorkflowStep $step) => $step->isRequestStep() || $step->isPaymentStep())
            ->values();
    }

    public function stepAt(Voucher $voucher, ?int $position): ?WorkflowStep
    {
        if (! $position) {
            return null;
        }

        return $this->applicableSteps($voucher)->firstWhere('position', $position);
    }

    public function nextStepAfter(Voucher $voucher, int $position): ?WorkflowStep
    {
        return $this->approvalSteps($voucher)
            ->first(fn (WorkflowStep $step) => $step->position > $position);
    }

    /* ------------------------------------------------------------- assignment */

    /** The people who may act at a step, resolved against this voucher. */
    public function assigneesFor(Voucher $voucher, WorkflowStep $step): Collection
    {
        if ($step->assigned_user_id) {
            $user = User::where('company_id', $voucher->company_id)->find($step->assigned_user_id);

            return new Collection($user ? [$user] : []);
        }

        $department = $voucher->department;

        $candidate = match ($step->role) {
            'employee' => $voucher->requester_id,
            'hod' => $department?->hod_user_id,
            'manager' => $department?->manager_user_id,
            default => null,
        };

        if ($candidate) {
            $user = User::where('company_id', $voucher->company_id)->find($candidate);

            if ($user) {
                return new Collection([$user]);
            }
        }

        // Fall back to everyone in the tenant holding the step's role.
        if ($step->role === 'custom') {
            return new Collection;
        }

        return User::query()
            ->where('company_id', $voucher->company_id)
            ->where('role', $step->role)
            ->where('status', 'active')
            ->get();
    }

    public function canActOnStep(User $user, Voucher $voucher, WorkflowStep $step): bool
    {
        if ($user->company_id !== $voucher->company_id) {
            return false;
        }

        // Company admins may act at any step of their own tenant as an override;
        // the action is still written to the timeline under their own name.
        if ($user->isCompanyAdmin()) {
            return true;
        }

        return $this->assigneesFor($voucher, $step)->contains(fn (User $u) => $u->id === $user->id);
    }

    /* ---------------------------------------------------------------- actions */

    /**
     * What this user may do with this voucher right now — the single source the
     * API, the web UI and the mobile app all read.
     */
    public function availableActions(User $user, Voucher $voucher): array
    {
        $actions = [
            'view' => true,
            'edit' => false,
            'delete' => false,
            'submit' => false,
            'sign' => false,
            'submit_signed' => false,
            'approve' => false,
            'reject' => false,
            'request_changes' => false,
            'cancel' => false,
            'comment' => true,
            'print' => false,
            'download' => false,
            'pay' => false,
        ];

        $isOwner = $voucher->requester_id === $user->id;
        $isAdmin = $user->isCompanyAdmin() || $user->isSuperAdmin();

        // Printing and download follow the step's grant; the owner and admins keep
        // it at every stage, which is what the design's "print at any stage" means.
        $step = $voucher->status === Voucher::STATUS_IN_REVIEW
            ? $this->stepAt($voucher, $voucher->current_step_position)
            : null;

        $actions['print'] = $isOwner || $isAdmin || $voucher->isTerminal() || ($step?->can_print ?? false);
        $actions['download'] = $isOwner || $isAdmin || $voucher->isTerminal() || ($step?->can_download ?? false);

        if (($isOwner || $isAdmin) && $voucher->isEditable()) {
            $actions['edit'] = true;
            $actions['submit'] = true;
            $actions['delete'] = $voucher->status === Voucher::STATUS_DRAFT;
        }

        if (($isOwner || $isAdmin) && $voucher->status === Voucher::STATUS_IN_REVIEW) {
            $actions['cancel'] = true;
        }

        // Payment is not another review step. The approval chain ends when the
        // last approver signs off; releasing the money is a separate function,
        // performed against an already-approved voucher by whoever the workflow
        // gave the pay capability to. Keeping the two apart is also what lets a
        // company route approval one way and disbursement another.
        if ($voucher->isAwaitingPayment() && $this->canPay($user, $voucher)) {
            $actions['pay'] = true;
        }

        if (! $step || ! $this->canActOnStep($user, $voucher, $step)) {
            return $actions;
        }

        $signed = $voucher->step_signed_at !== null;

        if ($step->can_sign && ! $signed) {
            $actions['sign'] = true;
        }

        // A signing-only step submits onward once signed; the approve/reject
        // decision belongs to a later step, not this one.
        if ($step->can_sign && ! $step->can_approve && $signed) {
            $actions['submit_signed'] = true;
        }

        if ($step->can_approve && (! $step->requires_signature || $signed || ! $step->can_sign)) {
            $actions['approve'] = true;
        }

        $actions['reject'] = $step->can_reject;
        $actions['request_changes'] = $step->can_request_changes;

        return $actions;
    }

    /**
     * Whether this user holds a paying step in the voucher's own workflow.
     *
     * Read from the step's flag rather than from the user's job title: a tenant
     * that calls the role "Treasury" and one that calls it "Cashier" are both
     * answered by the same question — does their step carry `can_pay`.
     */
    public function canPay(User $user, Voucher $voucher): bool
    {
        if ($user->company_id !== $voucher->company_id) {
            return false;
        }

        if ($user->isCompanyAdmin()) {
            return true;
        }

        return $this->applicableSteps($voucher)
            ->filter(fn (WorkflowStep $step) => $step->can_pay)
            ->contains(fn (WorkflowStep $step) => $this->assigneesFor($voucher, $step)
                ->contains(fn (User $u) => $u->id === $user->id));
    }

    /**
     * Approved → paid. The end of the lifecycle: the money has moved, and the
     * voucher leaves the cashier's queue for the reports.
     */
    public function pay(Voucher $voucher, User $actor, array $details, ?string $signatureData = null): Voucher
    {
        $this->guard($voucher->status === Voucher::STATUS_APPROVED, 'Only an approved voucher can be paid.');
        $this->guard($voucher->paid_at === null, 'This voucher has already been paid.');
        $this->guard($this->canPay($actor, $voucher), 'You may not release payment on this voucher.');

        $step = $this->applicableSteps($voucher)->first(fn (WorkflowStep $s) => $s->can_pay);

        return DB::transaction(function () use ($voucher, $actor, $details, $signatureData, $step) {
            $signature = $signatureData ?: $actor->signature_data;

            $this->record($voucher, $actor, 'paid', $details['note'] ?? null, $signature, $step);

            $voucher->forceFill([
                'status' => Voucher::STATUS_PAID,
                'paid_at' => now(),
                'paid_by_id' => $actor->id,
                'payment_reference' => $details['payment_reference'] ?? null,
                'payment_date' => $details['payment_date'] ?? now()->toDateString(),
                'payment_method' => $details['payment_method'] ?? $voucher->payment_method,
                'cheque_number' => $details['cheque_number'] ?? $voucher->cheque_number,
                'received_by' => $details['received_by'] ?? $voucher->received_by,
                'current_step_position' => null,
                'step_signed_at' => null,
            ])->save();

            $this->audit->log(
                'voucher.paid',
                "Released payment on voucher {$voucher->number}",
                $voucher,
                ['status' => Voucher::STATUS_APPROVED],
                ['status' => Voucher::STATUS_PAID, 'reference' => $voucher->payment_reference],
            );

            $this->notifier->toUser(
                $voucher->requester,
                'voucher.paid',
                "{$voucher->number} has been paid",
                "{$voucher->number} imelipwa",
                "{$actor->name} released {$voucher->currency} ".number_format((float) $voucher->amount)
                    .($voucher->payment_reference ? " · ref {$voucher->payment_reference}" : '').'.',
                "{$actor->name} ametoa {$voucher->currency} ".number_format((float) $voucher->amount)
                    .($voucher->payment_reference ? " · kumb. {$voucher->payment_reference}" : '').'.',
                $voucher,
                'ph-check-circle',
            );

            return $voucher->fresh();
        });
    }

    private function guard(bool $allowed, string $message): void
    {
        if (! $allowed) {
            throw new RuntimeException($message);
        }
    }

    /** Draft (or returned-for-changes) → the first applicable approval step. */
    public function submit(Voucher $voucher, User $actor, ?string $comment = null): Voucher
    {
        $this->guard($voucher->isEditable(), 'This voucher has already been submitted.');

        $resubmission = $voucher->status === Voucher::STATUS_CHANGES_REQUESTED;
        $first = $this->approvalSteps($voucher)->first();

        return DB::transaction(function () use ($voucher, $actor, $comment, $first, $resubmission) {
            $this->record($voucher, $actor, $resubmission ? 'resubmitted' : 'submitted', $comment, null, $first);

            if (! $first) {
                // A workflow with no approval gate completes on submission.
                $voucher->forceFill([
                    'status' => Voucher::STATUS_APPROVED,
                    'current_step_position' => null,
                    'step_signed_at' => null,
                    'submitted_at' => $voucher->submitted_at ?? now(),
                    'approved_at' => now(),
                ])->save();
            } else {
                $voucher->forceFill([
                    'status' => Voucher::STATUS_IN_REVIEW,
                    'current_step_position' => $first->position,
                    'step_signed_at' => null,
                    'submitted_at' => $voucher->submitted_at ?? now(),
                ])->save();

                $this->notifyStep($voucher, $first);
            }

            $this->audit->log(
                $resubmission ? 'voucher.resubmitted' : 'voucher.submitted',
                "Submitted voucher {$voucher->number}",
                $voucher,
                ['status' => $resubmission ? 'changes_requested' : 'draft'],
                ['status' => $voucher->status],
            );

            return $voucher->fresh();
        });
    }

    /** Applies a signature at the current step. Signing never approves. */
    public function sign(Voucher $voucher, User $actor, ?string $signatureData, ?string $comment = null): Voucher
    {
        $step = $this->requireActionableStep($voucher, $actor, 'sign');
        $this->guard($step->can_sign, 'This step does not carry a signature.');
        $this->guard($voucher->step_signed_at === null, 'This voucher is already signed at this step.');

        return DB::transaction(function () use ($voucher, $actor, $signatureData, $comment, $step) {
            $signature = $signatureData ?: $actor->signature_data;
            $this->guard((bool) $signature, 'A signature is required.');

            $this->record($voucher, $actor, 'signed', $comment, $signature, $step);
            $voucher->forceFill(['step_signed_at' => now()])->save();

            $this->audit->log('voucher.signed', "Signed voucher {$voucher->number}", $voucher);

            $this->notifier->toUser(
                $voucher->requester,
                'voucher.signed',
                "{$voucher->number} signed by {$actor->name}",
                "{$voucher->number} imesainiwa na {$actor->name}",
                "{$step->name} complete. The voucher continues along the approval route.",
                "{$step->name} imekamilika. Vocha inaendelea kwenye njia ya idhini.",
                $voucher,
                'ph-signature',
            );

            return $voucher->fresh();
        });
    }

    /** A signing-only step hands the signed voucher to the next step. */
    public function submitSigned(Voucher $voucher, User $actor, ?string $comment = null): Voucher
    {
        $step = $this->requireActionableStep($voucher, $actor, 'submit_signed');
        $this->guard($voucher->step_signed_at !== null, 'Sign the voucher before submitting it onward.');

        return DB::transaction(function () use ($voucher, $actor, $comment, $step) {
            $this->record($voucher, $actor, 'forwarded', $comment, null, $step);
            $this->advance($voucher, $step);

            $this->audit->log('voucher.forwarded', "Submitted signed voucher {$voucher->number} onward", $voucher);

            return $voucher->fresh();
        });
    }

    public function approve(Voucher $voucher, User $actor, ?string $comment = null, ?string $signatureData = null): Voucher
    {
        $step = $this->requireActionableStep($voucher, $actor, 'approve');
        $this->guard($step->can_approve, 'This step may not approve — it signs only.');

        return DB::transaction(function () use ($voucher, $actor, $comment, $signatureData, $step) {
            // A step configured to both sign and approve captures its mark here.
            if ($step->can_sign && $voucher->step_signed_at === null) {
                $signature = $signatureData ?: $actor->signature_data;

                if ($signature) {
                    $this->record($voucher, $actor, 'signed', null, $signature, $step);
                    $voucher->forceFill(['step_signed_at' => now()])->save();
                }
            }

            $this->record($voucher, $actor, 'approved', $comment, null, $step);
            $this->advance($voucher, $step);

            $this->audit->log('voucher.approved', "Approved voucher {$voucher->number}", $voucher);

            return $voucher->fresh();
        });
    }

    public function reject(Voucher $voucher, User $actor, string $comment): Voucher
    {
        $step = $this->requireActionableStep($voucher, $actor, 'reject');
        $this->guard($step->can_reject, 'This step may not reject.');

        return DB::transaction(function () use ($voucher, $actor, $comment, $step) {
            $this->record($voucher, $actor, 'rejected', $comment, null, $step);

            $voucher->forceFill([
                'status' => Voucher::STATUS_REJECTED,
                'current_step_position' => null,
                'step_signed_at' => null,
                'rejected_at' => now(),
            ])->save();

            $this->audit->log('voucher.rejected', "Rejected voucher {$voucher->number}", $voucher);

            $this->notifier->toUser(
                $voucher->requester,
                'voucher.rejected',
                "{$voucher->number} was rejected",
                "{$voucher->number} imekataliwa",
                "{$actor->name}: {$comment}",
                "{$actor->name}: {$comment}",
                $voucher,
                'ph-x-circle',
            );

            return $voucher->fresh();
        });
    }

    public function requestChanges(Voucher $voucher, User $actor, string $comment): Voucher
    {
        $step = $this->requireActionableStep($voucher, $actor, 'request_changes');
        $this->guard($step->can_request_changes, 'This step may not request changes.');

        return DB::transaction(function () use ($voucher, $actor, $comment, $step) {
            $this->record($voucher, $actor, 'changes_requested', $comment, null, $step);

            $voucher->forceFill([
                'status' => Voucher::STATUS_CHANGES_REQUESTED,
                'current_step_position' => null,
                'step_signed_at' => null,
            ])->save();

            $this->audit->log('voucher.changes_requested', "Requested changes on voucher {$voucher->number}", $voucher);

            $this->notifier->toUser(
                $voucher->requester,
                'voucher.changes_requested',
                "{$voucher->number} needs changes",
                "{$voucher->number} inahitaji mabadiliko",
                "{$actor->name}: {$comment}",
                "{$actor->name}: {$comment}",
                $voucher,
                'ph-arrow-u-up-left',
            );

            return $voucher->fresh();
        });
    }

    public function cancel(Voucher $voucher, User $actor, ?string $comment = null): Voucher
    {
        $this->guard(! $voucher->isTerminal(), 'This voucher is already closed.');

        return DB::transaction(function () use ($voucher, $actor, $comment) {
            $this->record($voucher, $actor, 'cancelled', $comment, null, null);

            $voucher->forceFill([
                'status' => Voucher::STATUS_CANCELLED,
                'current_step_position' => null,
                'step_signed_at' => null,
            ])->save();

            $this->audit->log('voucher.cancelled', "Cancelled voucher {$voucher->number}", $voucher);

            return $voucher->fresh();
        });
    }

    /* ---------------------------------------------------------------- internals */

    private function requireActionableStep(Voucher $voucher, User $actor, string $action): WorkflowStep
    {
        $this->guard($voucher->status === Voucher::STATUS_IN_REVIEW, 'This voucher is not currently under review.');

        $step = $this->stepAt($voucher, $voucher->current_step_position);
        $this->guard((bool) $step, 'This voucher has no active approval step.');
        $this->guard($this->canActOnStep($actor, $voucher, $step), 'This step is not assigned to you.');
        $this->guard($this->availableActions($actor, $voucher)[$action] ?? false, 'That action is not available at this step.');

        return $step;
    }

    /** Moves to the next applicable step, or completes the voucher. */
    private function advance(Voucher $voucher, WorkflowStep $from): void
    {
        $next = $this->nextStepAfter($voucher, $from->position);

        if ($next) {
            $voucher->forceFill([
                'status' => Voucher::STATUS_IN_REVIEW,
                'current_step_position' => $next->position,
                'step_signed_at' => null,
            ])->save();

            $this->notifyStep($voucher, $next);

            return;
        }

        $voucher->forceFill([
            'status' => Voucher::STATUS_APPROVED,
            'current_step_position' => null,
            'step_signed_at' => null,
            'approved_at' => now(),
        ])->save();

        $this->notifier->toUser(
            $voucher->requester,
            'voucher.approved',
            "{$voucher->number} approved",
            "{$voucher->number} imeidhinishwa",
            'Approved and sent for payment.',
            'Imeidhinishwa na kupelekwa kwa malipo.',
            $voucher,
            'ph-seal-check',
        );

        // The approval chain is done; the money has not moved. Whoever carries
        // the pay capability now has it on their queue and should be told so.
        foreach ($this->applicableSteps($voucher)->filter(fn (WorkflowStep $s) => $s->can_pay) as $payStep) {
            foreach ($this->assigneesFor($voucher, $payStep) as $payer) {
                $this->notifier->toUser(
                    $payer,
                    'voucher.awaiting_payment',
                    "{$voucher->number} is ready for payment",
                    "{$voucher->number} ipo tayari kulipwa",
                    "{$voucher->currency} ".number_format((float) $voucher->amount)." to {$voucher->payee}.",
                    "{$voucher->currency} ".number_format((float) $voucher->amount)." kwa {$voucher->payee}.",
                    $voucher,
                    'ph-wallet',
                );
            }
        }
    }

    private function notifyStep(Voucher $voucher, WorkflowStep $step): void
    {
        $verb = $step->can_approve ? 'approval' : 'signature';
        $verbSw = $step->can_approve ? 'idhini' : 'sahihi';

        foreach ($this->assigneesFor($voucher, $step) as $assignee) {
            $this->notifier->toUser(
                $assignee,
                'voucher.awaiting',
                "{$voucher->number} needs your {$verb}",
                "{$voucher->number} inahitaji {$verbSw} yako",
                "{$voucher->requester?->name} submitted {$voucher->currency} ".number_format((float) $voucher->amount)." — {$voucher->purpose}.",
                "{$voucher->requester?->name} alituma {$voucher->currency} ".number_format((float) $voucher->amount)." — {$voucher->purpose}.",
                $voucher,
                $step->can_approve ? 'ph-seal-check' : 'ph-signature',
            );
        }
    }

    public function record(
        Voucher $voucher,
        User $actor,
        string $action,
        ?string $comment = null,
        ?string $signature = null,
        ?WorkflowStep $step = null,
    ): VoucherApproval {
        return VoucherApproval::create([
            'voucher_id' => $voucher->id,
            'company_id' => $voucher->company_id,
            'workflow_step_id' => $step?->id,
            'step_position' => $step?->position,
            'step_name' => $step?->name,
            'step_role' => $step?->role,
            'actor_id' => $actor->id,
            'actor_name' => $actor->name,
            'actor_role' => $actor->role,
            'action' => $action,
            'comment' => $comment,
            'signature_data' => $signature,
            'ip' => request()?->ip(),
            'user_agent' => substr((string) request()?->userAgent(), 0, 255),
            'acted_at' => now(),
        ]);
    }
}
