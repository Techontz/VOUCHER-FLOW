<?php

namespace App\Services;

use App\Models\Voucher;
use App\Models\WorkflowStep;

/**
 * Human status text, derived from the voucher's own workflow rather than a fixed
 * list — so a tenant whose second step is "Finance verification" reads
 * "Awaiting Finance verification", not a hard-coded "Awaiting HOD signature".
 */
class StatusPresenter
{
    public function __construct(private readonly WorkflowEngine $engine) {}

    /** @return array{key:string,label:string,label_sw:string,tag:string,stage:?int} */
    public function present(Voucher $voucher): array
    {
        $step = $voucher->status === Voucher::STATUS_IN_REVIEW
            ? $this->engine->stepAt($voucher, $voucher->current_step_position)
            : null;

        return match ($voucher->status) {
            Voucher::STATUS_DRAFT => $this->make('draft', 'Draft', 'Rasimu', 'tag-neutral'),

            Voucher::STATUS_CHANGES_REQUESTED => $this->make(
                'changes_requested', 'Changes requested', 'Mabadiliko yameombwa', 'tag-accent-2'
            ),

            // Approved is no longer the end of the road: the money still has to
            // move, and saying "completed" here would hide the cashier's work.
            Voucher::STATUS_APPROVED => $this->make(
                'awaiting_payment', 'Approved — awaiting payment', 'Imeidhinishwa — inasubiri malipo', 'tag-info'
            ),

            Voucher::STATUS_PAID => $this->make(
                'paid', 'Paid & completed', 'Imelipwa na kukamilika', 'tag-accent'
            ),

            Voucher::STATUS_REJECTED => $this->make('rejected', 'Rejected', 'Imekataliwa', 'tag-accent-2'),

            Voucher::STATUS_CANCELLED => $this->make('cancelled', 'Cancelled', 'Imefutwa', 'tag-neutral'),

            default => $this->inReview($voucher, $step),
        };
    }

    private function inReview(Voucher $voucher, ?WorkflowStep $step): array
    {
        if (! $step) {
            return $this->make('in_review', 'In review', 'Inapitiwa', 'tag-outline', $voucher->current_step_position);
        }

        $role = WorkflowStep::roleLabel($step->role);
        $signed = $voucher->step_signed_at !== null;

        // Signing-only step: sign, then submit onward. The two states read
        // differently because the holder has different work to do in each.
        if ($step->can_sign && ! $step->can_approve) {
            return $signed
                ? $this->make('signed_pending_submit', 'Signed — ready to submit', 'Imesainiwa — tayari kutumwa', 'tag-outline', $step->position)
                : $this->make('awaiting_signature', "Awaiting {$role} signature", "Inasubiri sahihi ya {$role}", 'tag-outline', $step->position);
        }

        if ($step->can_approve) {
            return $this->make('awaiting_approval', "Awaiting {$role} approval", "Inasubiri idhini ya {$role}", 'tag-outline', $step->position);
        }

        return $this->make('awaiting_review', "Awaiting {$step->name}", "Inasubiri {$step->name}", 'tag-outline', $step->position);
    }

    private function make(string $key, string $label, string $labelSw, string $tag, ?int $stage = null): array
    {
        return ['key' => $key, 'label' => $label, 'label_sw' => $labelSw, 'tag' => $tag, 'stage' => $stage];
    }
}
