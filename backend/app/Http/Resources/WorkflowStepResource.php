<?php

namespace App\Http\Resources;

use App\Models\WorkflowStep;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class WorkflowStepResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $locale = app()->getLocale();

        return [
            'id' => $this->id,
            'position' => $this->position,
            'name' => $this->name,
            'name_sw' => $this->name_sw,
            'label' => $this->label($locale),
            'role' => $this->role,
            'role_label' => WorkflowStep::roleLabel($this->role),
            'assigned_user_id' => $this->assigned_user_id,
            'assigned_user' => $this->whenLoaded('assignedUser', fn () => $this->assignedUser
                ? ['id' => $this->assignedUser->id, 'name' => $this->assignedUser->name]
                : null),
            'assignee_hint' => $this->assignee_hint,
            'can_sign' => (bool) $this->can_sign,
            'can_approve' => (bool) $this->can_approve,
            'can_reject' => (bool) $this->can_reject,
            'can_request_changes' => (bool) $this->can_request_changes,
            'can_print' => (bool) $this->can_print,
            'can_download' => (bool) $this->can_download,
            'requires_signature' => (bool) $this->requires_signature,
            'min_amount' => $this->min_amount !== null ? (float) $this->min_amount : null,
            'max_amount' => $this->max_amount !== null ? (float) $this->max_amount : null,
            'is_request_step' => $this->isRequestStep(),
        ];
    }
}
