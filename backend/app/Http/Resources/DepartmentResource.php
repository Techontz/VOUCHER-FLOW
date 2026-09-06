<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class DepartmentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'code' => $this->code,
            'cost_centre' => $this->cost_centre,
            'is_active' => (bool) $this->is_active,
            'hod_user_id' => $this->hod_user_id,
            'manager_user_id' => $this->manager_user_id,
            'hod' => $this->whenLoaded('hod', fn () => $this->hod ? ['id' => $this->hod->id, 'name' => $this->hod->name] : null),
            'manager' => $this->whenLoaded('manager', fn () => $this->manager ? ['id' => $this->manager->id, 'name' => $this->manager->name] : null),
            'users_count' => $this->whenCounted('users'),
            'vouchers_count' => $this->whenCounted('vouchers'),
            'spend' => $this->when(isset($this->spend), fn () => (float) $this->spend),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
