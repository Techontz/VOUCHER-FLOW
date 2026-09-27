<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class WorkflowResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'name_sw' => $this->name_sw,
            'label' => app()->getLocale() === 'sw' && $this->name_sw ? $this->name_sw : $this->name,
            'description' => $this->description,
            'voucher_type_id' => $this->voucher_type_id,
            'voucher_type' => $this->whenLoaded('voucherType', fn () => $this->voucherType
                ? ['id' => $this->voucherType->id, 'name' => $this->voucherType->name, 'name_sw' => $this->voucherType->name_sw]
                : null),
            'is_default' => (bool) $this->is_default,
            'is_active' => (bool) $this->is_active,
            'version' => $this->version,
            'route_summary' => $this->whenLoaded('steps', fn () => $this->routeSummary().' → Completed'),
            'steps' => WorkflowStepResource::collection($this->whenLoaded('steps')),
            'vouchers_count' => $this->whenCounted('vouchers'),
            'in_flight_count' => $this->whenCounted('in_flight_count', fn () => (int) $this->in_flight_count),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
