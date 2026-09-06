<?php

namespace App\Services;

use App\Models\Voucher;
use App\Models\VoucherApproval;
use App\Models\WorkflowStep;

/**
 * Builds the approval timeline shown on the voucher detail screen.
 *
 * Generated from the company's configured workflow joined against what actually
 * happened, so a tenant with four steps or a signing-only manager renders
 * correctly without any special-casing.
 */
class TimelineBuilder
{
    public function __construct(private readonly WorkflowEngine $engine) {}

    public function build(Voucher $voucher): array
    {
        $steps = $this->engine->applicableSteps($voucher);
        $approvals = $voucher->relationLoaded('approvals') ? $voucher->approvals : $voucher->approvals()->get();

        $completed = $voucher->status === Voucher::STATUS_APPROVED;
        $rejected = $voucher->status === Voucher::STATUS_REJECTED;
        $returned = $voucher->status === Voucher::STATUS_CHANGES_REQUESTED;
        $currentPosition = $voucher->current_step_position;

        $rows = [];

        foreach ($steps as $step) {
            $atThis = $currentPosition === $step->position && ! $completed && ! $rejected;
            $done = $completed || ($currentPosition !== null && $step->position < $currentPosition) || ($rejected && $this->hasAction($approvals, $step, ['approved', 'signed', 'forwarded']));

            $stepEvents = $approvals->filter(fn (VoucherApproval $a) => $a->step_position === $step->position)->values();
            $terminalEvent = $stepEvents->last(fn (VoucherApproval $a) => in_array($a->action, ['rejected', 'changes_requested'], true));
            $isRejectHere = $terminalEvent?->action === 'rejected';
            $isReturnHere = $terminalEvent?->action === 'changes_requested';

            [$act, $actSw, $when, $comment] = $this->describe($voucher, $step, $stepEvents, $atThis, $done, $completed);

            $good = $done && ! $isRejectHere && ! $isReturnHere;
            $bad = $isRejectHere || $isReturnHere;

            $rows[] = [
                'position' => $step->position,
                'name' => $step->name,
                'name_sw' => $step->name_sw,
                'sub' => 'Step '.$step->position.' · '.WorkflowStep::roleLabel($step->role),
                'sub_sw' => 'Hatua '.$step->position.' · '.WorkflowStep::roleLabel($step->role),
                'person' => $this->personFor($voucher, $step, $stepEvents),
                'act' => $act,
                'act_sw' => $actSw,
                'when' => $when,
                'comment' => $comment,
                'signature' => $stepEvents->firstWhere('action', 'signed')?->signature_data,
                'capabilities' => $step->capabilities(),
                'capability_text' => $this->capabilityText($step),
                'state' => $bad ? 'rejected' : ($good ? 'done' : ($atThis ? 'current' : 'pending')),
                'icon' => $bad ? 'ph-x-circle' : ($good ? 'ph-check-circle' : ($atThis ? 'ph-hourglass-medium' : 'ph-circle-dashed')),
            ];
        }

        $rows[] = [
            'position' => null,
            'name' => 'Completed',
            'name_sw' => 'Imekamilika',
            'sub' => 'System',
            'sub_sw' => 'Mfumo',
            'person' => 'VouchFlow',
            'act' => $completed ? 'Voucher completed' : ($rejected ? 'Closed as rejected' : ($returned ? 'Returned to requester' : 'Not completed')),
            'act_sw' => $completed ? 'Vocha imekamilika' : ($rejected ? 'Imefungwa kama iliyokataliwa' : ($returned ? 'Imerudishwa kwa mwombaji' : 'Haijakamilika')),
            'when' => $completed ? $voucher->approved_at?->toIso8601String() : ($rejected ? $voucher->rejected_at?->toIso8601String() : null),
            'comment' => $completed && $voucher->verification_code
                ? "Approval ID {$voucher->verification_code} · PDF generated with all captured marks."
                : null,
            'signature' => null,
            'capabilities' => ['print' => true, 'download' => true],
            'capability_text' => 'Print · Download PDF · Share',
            'state' => $completed ? 'done' : ($rejected ? 'rejected' : 'pending'),
            'icon' => $completed ? 'ph-seal-check' : ($rejected ? 'ph-x-circle' : 'ph-circle-dashed'),
        ];

        return $rows;
    }

    private function hasAction($approvals, WorkflowStep $step, array $actions): bool
    {
        return $approvals->contains(fn (VoucherApproval $a) => $a->step_position === $step->position && in_array($a->action, $actions, true));
    }

    private function describe(Voucher $voucher, WorkflowStep $step, $events, bool $atThis, bool $done, bool $completed): array
    {
        $latest = $events->last();

        if ($step->isRequestStep()) {
            if ($voucher->status === Voucher::STATUS_DRAFT) {
                return ['Draft — not submitted', 'Rasimu — haijatumwa', null, null];
            }

            $count = $voucher->attachments_count ?? $voucher->attachments()->count();

            return [
                'Created & submitted',
                'Imetengenezwa na kutumwa',
                $voucher->submitted_at?->toIso8601String(),
                $count > 0 ? "{$count} supporting document(s) attached." : null,
            ];
        }

        $rejectEvent = $events->last(fn (VoucherApproval $a) => $a->action === 'rejected');
        if ($rejectEvent) {
            return ['Rejected', 'Imekataliwa', $rejectEvent->acted_at?->toIso8601String(), $rejectEvent->comment];
        }

        $changesEvent = $events->last(fn (VoucherApproval $a) => $a->action === 'changes_requested');
        if ($changesEvent) {
            return ['Changes requested', 'Mabadiliko yameombwa', $changesEvent->acted_at?->toIso8601String(), $changesEvent->comment];
        }

        $approveEvent = $events->last(fn (VoucherApproval $a) => $a->action === 'approved');
        if ($approveEvent) {
            return ['Approved', 'Imeidhinishwa', $approveEvent->acted_at?->toIso8601String(), $approveEvent->comment ?: 'Cleared to continue.'];
        }

        $forwardEvent = $events->last(fn (VoucherApproval $a) => $a->action === 'forwarded');
        $signEvent = $events->last(fn (VoucherApproval $a) => $a->action === 'signed');

        if ($signEvent && $forwardEvent) {
            return [
                'Reviewed & signed',
                'Imepitiwa na kusainiwa',
                $signEvent->acted_at?->toIso8601String(),
                $forwardEvent->comment ?: 'Signature applied and forwarded to the next step.',
            ];
        }

        if ($signEvent && $atThis) {
            return [
                'Signed — not yet submitted onward',
                'Imesainiwa — haijatumwa mbele',
                $signEvent->acted_at?->toIso8601String(),
                'Signature captured. This step signs only; it makes no approval decision.',
            ];
        }

        if ($atThis) {
            return $step->can_approve
                ? ['Awaiting approval', 'Inasubiri idhini', null, null]
                : ['Awaiting signature', 'Inasubiri sahihi', null, null];
        }

        if ($done) {
            return ['Passed', 'Imepita', $latest?->acted_at?->toIso8601String(), $latest?->comment];
        }

        return ['Not started', 'Haijaanza', null, null];
    }

    private function personFor(Voucher $voucher, WorkflowStep $step, $events): string
    {
        if ($actor = $events->last()?->actor_name) {
            return $actor;
        }

        if ($step->isRequestStep()) {
            return $voucher->requester?->name ?? 'Requester';
        }

        $assignees = $this->engine->assigneesFor($voucher, $step);

        return $assignees->first()?->name ?? ($step->assignee_hint ?: WorkflowStep::roleLabel($step->role));
    }

    private function capabilityText(WorkflowStep $step): string
    {
        $labels = [
            'can_sign' => 'Sign',
            'can_approve' => 'Approve',
            'can_reject' => 'Reject',
            'can_request_changes' => 'Request changes',
            'can_print' => 'Print / PDF',
        ];

        $on = [];

        foreach ($labels as $field => $label) {
            if ($step->{$field}) {
                $on[] = $label;
            }
        }

        return $on ? implode(' · ', $on) : 'View only';
    }
}
