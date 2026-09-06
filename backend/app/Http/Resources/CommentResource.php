<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class CommentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'body' => $this->body,
            'user' => $this->whenLoaded('user', fn () => $this->user ? [
                'id' => $this->user->id,
                'name' => $this->user->name,
                'initials' => $this->user->initials(),
                'role_label' => $this->user->role,
                'department' => $this->user->department?->name,
            ] : null),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
