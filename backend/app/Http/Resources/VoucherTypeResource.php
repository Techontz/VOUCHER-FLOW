<?php

namespace App\Http\Resources;

use App\Services\VoucherNumberGenerator;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class VoucherTypeResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'name_sw' => $this->name_sw,
            'label' => $this->label(app()->getLocale()),
            'code' => $this->code,
            'prefix' => $this->prefix,
            'number_format' => $this->number_format,
            'seq_padding' => $this->seq_padding,
            'next_number' => $this->next_number,
            'reset_yearly' => (bool) $this->reset_yearly,
            'is_active' => (bool) $this->is_active,
            'sort_order' => $this->sort_order,
            'next_number_preview' => app(VoucherNumberGenerator::class)->preview($this->resource),
            'vouchers_count' => $this->whenCounted('vouchers'),
        ];
    }
}
