<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PlanResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $locale = app()->getLocale();

        return [
            'id' => $this->id,
            'code' => $this->code,
            'name' => $this->name,
            'label' => $locale === 'sw' && $this->name_sw ? $this->name_sw : $this->name,
            'blurb' => $locale === 'sw' && $this->blurb_sw ? $this->blurb_sw : $this->blurb,
            'price' => (float) $this->price,
            'currency' => $this->currency,
            'billing_cycle' => $this->billing_cycle,
            'max_users' => $this->max_users,
            'max_vouchers_per_month' => $this->max_vouchers_per_month,
            'max_departments' => $this->max_departments,
            'max_approval_levels' => $this->max_approval_levels,
            'storage_mb' => $this->storage_mb,
            'trial_days' => $this->trial_days,
            'features' => $this->features ?? [],
            'is_active' => (bool) $this->is_active,
            'is_public' => (bool) $this->is_public,
            'sort_order' => $this->sort_order,
            'companies_count' => $this->whenCounted('companies'),
        ];
    }
}
