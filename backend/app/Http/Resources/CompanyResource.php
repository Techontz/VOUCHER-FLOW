<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class CompanyResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'slug' => $this->slug,
            'legal_name' => $this->legal_name,
            'email' => $this->email,
            'phone' => $this->phone,
            'address' => $this->address,
            'website' => $this->website,
            'country' => $this->country,
            'currency' => $this->currency,
            'locale' => $this->locale,
            'timezone' => $this->timezone,

            'logo_url' => $this->logo_path ? asset('storage/'.$this->logo_path) : null,
            'primary_color' => $this->primary_color,
            'accent_color' => $this->accent_color,
            'theme' => $this->theme,
            'voucher_footer_text' => $this->voucher_footer_text,

            'status' => $this->status,
            'is_usable' => $this->isUsable(),
            'is_expired' => $this->isExpired(),
            'days_remaining' => $this->daysRemaining(),
            'trial_ends_at' => $this->trial_ends_at?->toIso8601String(),
            'current_period_start' => $this->current_period_start?->toIso8601String(),
            'current_period_end' => $this->current_period_end?->toIso8601String(),
            'auto_renew' => (bool) $this->auto_renew,

            'plan' => new PlanResource($this->whenLoaded('plan')),
            'plan_id' => $this->plan_id,
            'settings' => $this->settings ?? [],

            'users_count' => $this->whenCounted('users'),
            'vouchers_count' => $this->whenCounted('vouchers'),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
