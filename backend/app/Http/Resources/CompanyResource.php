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
            'trading_name' => $this->trading_name,
            'document_name' => $this->documentName(),
            'initials' => $this->initials(),

            'email' => $this->email,
            'phone' => $this->phone,
            'alternative_phone' => $this->alternative_phone,
            'website' => $this->website,

            'address' => $this->address,
            'postal_address' => $this->postal_address,
            'city' => $this->city,
            'region' => $this->region,
            'country' => $this->country,

            'tin' => $this->tin,
            'registration_number' => $this->registration_number,
            'business_license_number' => $this->business_license_number,

            'contact_person' => $this->contact_person,
            'contact_email' => $this->contact_email,
            'contact_phone' => $this->contact_phone,

            'currency' => $this->currency,
            'locale' => $this->locale,
            'timezone' => $this->timezone,

            // Resolved through the model, so a path whose file was never
            // published reads as "no logo" rather than a broken image.
            'logo_url' => $this->logoUrl(),
            'logo_mark_url' => $this->logoMarkUrl(),
            'has_logo' => $this->logoUrl() !== null,

            'primary_color' => $this->primary_color,
            'secondary_color' => $this->secondary_color,
            'accent_color' => $this->accent_color,
            'theme' => $this->theme,
            'voucher_header_text' => $this->voucher_header_text,
            'voucher_footer_text' => $this->voucher_footer_text,

            'bank_name' => $this->bank_name,
            'bank_account_name' => $this->bank_account_name,
            'bank_account_number' => $this->bank_account_number,
            'bank_branch' => $this->bank_branch,
            'swift_code' => $this->swift_code,

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
