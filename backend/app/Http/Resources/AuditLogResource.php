<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class AuditLogResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'action' => $this->action,
            'description' => $this->description,
            'change_summary' => $this->change_summary,
            'entity_type' => $this->entity_type,
            'entity_id' => $this->entity_id,
            'actor' => [
                'id' => $this->actor_id,
                'name' => $this->actor_name ?? 'System',
                'role' => $this->actor_role,
                'initials' => collect(preg_split('/\s+/', trim((string) ($this->actor_name ?: 'System'))))
                    ->filter()->take(2)
                    ->map(fn ($w) => mb_strtoupper(mb_substr($w, 0, 1)))->implode(''),
            ],
            'company' => $this->whenLoaded('company', fn () => $this->company?->name),
            'company_id' => $this->company_id,
            'ip' => $this->ip,
            'user_agent' => $this->user_agent,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
