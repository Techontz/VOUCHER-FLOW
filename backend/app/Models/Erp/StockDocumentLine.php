<?php

namespace App\Models\Erp;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Tenancy comes through the parent document, which is always resolved first. */
class StockDocumentLine extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'stock_document_id' => 'integer',
            'product_id' => 'integer',
            'quantity' => 'decimal:4',
            'unit_cost' => 'decimal:2',
            'system_quantity' => 'decimal:4',
            'expiry_date' => 'date',
        ];
    }

    public function document(): BelongsTo
    {
        return $this->belongsTo(StockDocument::class, 'stock_document_id');
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
