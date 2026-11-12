<?php

namespace App\Models\Erp\Sales;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A named set of product prices. A customer follows one by its code. */
class PriceList extends Model
{
    use BelongsToTenant;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return ['company_id' => 'integer', 'is_default' => 'boolean', 'is_active' => 'boolean'];
    }

    public function items(): HasMany
    {
        return $this->hasMany(PriceListItem::class);
    }
}
