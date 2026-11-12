<?php

namespace App\Models\Erp\Production;

use App\Models\Erp\Product;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Tenancy comes through the parent bill of materials, which is always resolved first. */
class BomLine extends Model
{
    protected $table = 'production_bom_lines';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'bom_id' => 'integer',
            'product_id' => 'integer',
            'quantity' => 'decimal:4',
            'scrap_percent' => 'decimal:2',
            'position' => 'integer',
        ];
    }

    public function bom(): BelongsTo
    {
        return $this->belongsTo(Bom::class);
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
