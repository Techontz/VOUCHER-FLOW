<?php

namespace App\Models\Erp;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Customer extends Model
{
    use BelongsToTenant, SoftDeletes;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'credit_limit' => 'decimal:2',
            'payment_terms_days' => 'integer',
            'requires_prepayment' => 'boolean',
            'custom_fields' => 'array',
            'is_active' => 'boolean',
        ];
    }
}
