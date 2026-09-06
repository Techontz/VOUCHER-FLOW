<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class NotificationResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $locale = app()->getLocale();

        return [
            'id' => $this->id,
            'type' => $this->type,
            'icon' => $this->icon ?? 'ph-bell',
            'title' => $this->title($locale),
            'body' => $this->body($locale),
            'entity_type' => $this->entity_type,
            'entity_id' => $this->entity_id,
            'action_url' => $this->action_url,
            'is_unread' => $this->isUnread(),
            'read_at' => $this->read_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
