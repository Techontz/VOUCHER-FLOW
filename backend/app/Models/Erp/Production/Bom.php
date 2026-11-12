<?php

namespace App\Models\Erp\Production;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Product;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * What one batch of a finished product consumes. Versioned: a product may
 * have many versions, one of them active, and an order keeps the version it
 * was planned with even after another is activated.
 */
class Bom extends Model
{
    use BelongsToTenant;

    protected $table = 'production_boms';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'product_id' => 'integer',
            'work_centre_id' => 'integer',
            'version' => 'integer',
            'output_quantity' => 'decimal:3',
            'labour_cost' => 'decimal:2',
            'overhead_cost' => 'decimal:2',
            'is_active' => 'boolean',
            'activated_at' => 'datetime',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function lines(): HasMany
    {
        return $this->hasMany(BomLine::class)->orderBy('position')->orderBy('id');
    }

    public function workCentre(): BelongsTo
    {
        return $this->belongsTo(WorkCentre::class);
    }

    public function orders(): HasMany
    {
        return $this->hasMany(ProductionOrder::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    /** Labour and overhead for one finished unit. */
    public function conversionPerUnit(): float
    {
        return ((float) $this->labour_cost + (float) $this->overhead_cost) / max((float) $this->output_quantity, 0.0001);
    }
}
