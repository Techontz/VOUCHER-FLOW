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
            'name_sw' => $this->name_sw,
            'blurb_sw' => $this->blurb_sw,
            'blurb' => $locale === 'sw' && $this->blurb_sw ? $this->blurb_sw : $this->blurb,
            'price' => (float) $this->price,
            'price_yearly' => $this->price_yearly !== null ? (float) $this->price_yearly : null,
            'yearly_price' => $this->yearlyPrice(),
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
            'is_featured' => (bool) $this->is_featured,
            'modules' => $this->modules ?? [],
            // The apps it offers spelled out, so a client never has to know
            // that an empty list means all of them.
            'apps' => $this->apps(),
            'apps_count' => count($this->apps()),
            'all_apps' => $this->includesAllApps(),
            'allows_module_choice' => (bool) $this->allows_module_choice,
            'price_per_module' => (float) $this->price_per_module,
            'sort_order' => $this->sort_order,
            'companies_count' => $this->whenCounted('companies'),
            'subscriptions_count' => $this->whenCounted('subscriptions'),
        ];
    }
}
