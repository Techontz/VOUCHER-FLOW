<?php

namespace App\Http\Resources;

use App\Services\AmountFormatter;
use App\Services\StatusPresenter;
use App\Services\TimelineBuilder;
use App\Services\WorkflowEngine;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class VoucherResource extends JsonResource
{
    /** Set to true to include the timeline, attachments and comments. */
    public bool $detailed = false;

    public function detailed(bool $value = true): self
    {
        $this->detailed = $value;

        return $this;
    }

    public function toArray(Request $request): array
    {
        $status = app(StatusPresenter::class)->present($this->resource);
        $money = app(AmountFormatter::class);
        $locale = app()->getLocale();
        $user = $request->user();

        $data = [
            'id' => $this->id,
            'number' => $this->number,
            'status' => $this->status,
            'status_key' => $status['key'],
            'status_label' => $locale === 'sw' ? $status['label_sw'] : $status['label'],
            'status_label_en' => $status['label'],
            'status_label_sw' => $status['label_sw'],
            'status_tag' => $status['tag'],

            'payee' => $this->payee,
            'purpose' => $this->purpose,
            'description' => $this->description,
            'amount' => (float) $this->amount,
            'currency' => $this->currency,
            'amount_text' => $money->money((float) $this->amount, $this->currency),
            'amount_in_words' => $this->amount_in_words,

            'payment_method' => $this->payment_method,
            'account_ref' => $this->account_ref,

            // The instrument, and only the particulars that instrument uses.
            // A cash voucher carrying a set of null bank keys invites a client
            // to render empty rows for them.
            'kind' => $this->kind,
            ...($this->isBank() ? [
                'payee_bank' => $this->payee_bank,
                'payee_account_name' => $this->payee_account_name,
                'payee_account_number' => $this->payee_account_number,
                'payee_bank_branch' => $this->payee_bank_branch,
                'cheque_number' => $this->cheque_number,
            ] : [
                'cash_float' => $this->cash_float,
                'received_by' => $this->received_by,
            ]),

            'paid_at' => $this->paid_at?->toIso8601String(),
            'payment_reference' => $this->payment_reference,
            'payment_date' => $this->payment_date?->toDateString(),
            'paid_by' => $this->whenLoaded('paidBy', fn () => $this->paidBy
                ? ['id' => $this->paidBy->id, 'name' => $this->paidBy->name, 'job_title' => $this->paidBy->job_title]
                : null),
            'is_awaiting_payment' => $this->isAwaitingPayment(),
            'category' => $this->category,
            'cost_centre' => $this->cost_centre,
            'voucher_date' => $this->voucher_date?->toDateString(),
            'notes_to_approver' => $this->notes_to_approver,
            'verification_code' => $this->verification_code,

            'voucher_type_id' => $this->voucher_type_id,
            'voucher_type' => $this->whenLoaded('voucherType', fn () => [
                'id' => $this->voucherType->id,
                'name' => $this->voucherType->name,
                'label' => $this->voucherType->label($locale),
            ]),

            'department_id' => $this->department_id,
            'department' => $this->whenLoaded('department', fn () => $this->department
                ? ['id' => $this->department->id, 'name' => $this->department->name]
                : null),

            'requester_id' => $this->requester_id,
            'requester' => $this->whenLoaded('requester', fn () => $this->requester ? [
                'id' => $this->requester->id,
                'name' => $this->requester->name,
                'initials' => $this->requester->initials(),
                'job_title' => $this->requester->job_title,
            ] : null),

            'workflow_id' => $this->workflow_id,
            'current_step_position' => $this->current_step_position,
            'is_signed_at_current_step' => $this->isSignedAtCurrentStep(),
            'is_editable' => $this->isEditable(),
            'is_terminal' => $this->isTerminal(),

            'submitted_at' => $this->submitted_at?->toIso8601String(),
            'approved_at' => $this->approved_at?->toIso8601String(),
            'rejected_at' => $this->rejected_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),

            'attachments_count' => $this->whenCounted('attachments'),
            'comments_count' => $this->whenCounted('comments'),
        ];

        if ($user) {
            $engine = app(WorkflowEngine::class);
            $data['actions'] = $engine->availableActions($user, $this->resource);

            $step = $engine->stepAt($this->resource, $this->current_step_position);
            $data['current_step'] = $step ? [
                'id' => $step->id,
                'position' => $step->position,
                'name' => $step->label($locale),
                'role' => $step->role,
                'capabilities' => $step->capabilities(),
            ] : null;
        }

        if ($this->detailed) {
            $data['timeline'] = app(TimelineBuilder::class)->build($this->resource);
            $data['attachments'] = AttachmentResource::collection($this->whenLoaded('attachments'));
            $data['comments'] = CommentResource::collection($this->whenLoaded('comments'));
            $data['workflow'] = new WorkflowResource($this->whenLoaded('workflow'));
        }

        return $data;
    }
}
