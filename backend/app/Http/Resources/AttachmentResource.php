<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class AttachmentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->original_name,
            'mime_type' => $this->mime_type,
            'size_bytes' => (int) $this->size_bytes,
            'size' => $this->humanSize(),
            'is_image' => $this->isImage(),
            'icon' => $this->isImage() ? 'ph-image' : 'ph-file-pdf',
            'url' => route('api.vouchers.attachments.show', [
                'voucher' => $this->voucher_id,
                'attachment' => $this->id,
            ]),
            'uploaded_by' => $this->whenLoaded('uploader', fn () => $this->uploader?->name),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
