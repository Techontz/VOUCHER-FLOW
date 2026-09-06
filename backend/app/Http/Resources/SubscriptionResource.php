<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SubscriptionResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'status' => $this->status,
            'billing_cycle' => $this->billing_cycle,
            'amount' => (float) $this->amount,
            'currency' => $this->currency,
            'seats' => $this->seats,
            'starts_at' => $this->starts_at?->toIso8601String(),
            'trial_ends_at' => $this->trial_ends_at?->toIso8601String(),
            'current_period_start' => $this->current_period_start?->toIso8601String(),
            'current_period_end' => $this->current_period_end?->toIso8601String(),
            'cancel_at_period_end' => (bool) $this->cancel_at_period_end,
            'is_expired' => $this->isExpired(),
            'plan' => new PlanResource($this->whenLoaded('plan')),
            'company_id' => $this->company_id,
            'company' => $this->whenLoaded('company', fn () => $this->company?->name),
        ];
    }
}
