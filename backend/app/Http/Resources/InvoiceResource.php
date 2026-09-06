<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class InvoiceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'number' => $this->number,
            'description' => $this->description,
            'amount' => (float) $this->amount,
            'tax' => (float) $this->tax,
            'total' => (float) $this->total,
            'currency' => $this->currency,
            'amount_text' => $this->currency.' '.number_format((float) $this->total),
            'status' => $this->status,
            'status_tag' => match ($this->status) {
                'paid' => 'tag-accent',
                'pending' => 'tag-outline',
                default => 'tag-accent-2',
            },
            'method' => $this->method,
            'method_label' => match ($this->method) {
                'mobile_money' => 'Mobile Money',
                'card' => 'Card',
                'bank_transfer' => 'Bank transfer',
                default => '—',
            },
            'provider_ref' => $this->provider_ref,
            'failure_reason' => $this->failure_reason,
            'period_start' => $this->period_start?->toDateString(),
            'period_end' => $this->period_end?->toDateString(),
            'issued_at' => $this->issued_at?->toIso8601String(),
            'paid_at' => $this->paid_at?->toIso8601String(),
            'company' => $this->whenLoaded('company', fn () => $this->company?->name),
            'company_id' => $this->company_id,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
