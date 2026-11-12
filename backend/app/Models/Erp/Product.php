<?php

namespace App\Models\Erp;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Product extends Model
{
    use BelongsToTenant, SoftDeletes;

    public const TYPES = ['stock', 'service', 'raw_material', 'finished_good', 'packaging'];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'category_id' => 'integer',
            'unit_id' => 'integer',
            'cost_price' => 'decimal:2',
            'sale_price' => 'decimal:2',
            'reorder_level' => 'decimal:4',
            'track_batches' => 'boolean',
            'track_expiry' => 'boolean',
            'track_serials' => 'boolean',
            'custom_fields' => 'array',
            'is_active' => 'boolean',
        ];
    }

    /** A service is bought and sold but never sits on a shelf. */
    public function isStocked(): bool
    {
        return $this->type !== 'service';
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(ProductCategory::class, 'category_id');
    }

    public function unit(): BelongsTo
    {
        return $this->belongsTo(Unit::class);
    }

    public function balances(): HasMany
    {
        return $this->hasMany(StockBalance::class);
    }
}
