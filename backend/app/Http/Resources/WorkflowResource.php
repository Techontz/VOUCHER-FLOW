<?php

namespace App\Http\Resources;

use App\Models\WorkflowStep;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class WorkflowResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'description' => $this->description,
            'voucher_type_id' => $this->voucher_type_id,
            'is_default' => (bool) $this->is_default,
            'is_active' => (bool) $this->is_active,
            'version' => $this->version,
            'route_summary' => $this->whenLoaded('steps', fn () => $this->routeSummary().' → Completed'),
            'steps' => WorkflowStepResource::collection($this->whenLoaded('steps')),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
