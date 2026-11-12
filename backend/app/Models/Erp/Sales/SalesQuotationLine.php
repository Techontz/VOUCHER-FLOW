<?php

namespace App\Models\Erp\Sales;

use App\Models\Erp\Product;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** A line of a {@see SalesQuotation}; reached only through its tenant-scoped parent. */
class SalesQuotationLine extends Model
{
    protected $table = 'sales_quotation_lines';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'quotation_id' => 'integer',
            'product_id' => 'integer',
            'quantity' => 'decimal:3',
            'quantity_ordered' => 'decimal:3',
            'quantity_approved' => 'decimal:3',
            'quantity_loaded' => 'decimal:3',
            'quantity_received' => 'decimal:3',
            'quantity_invoiced' => 'decimal:3',
            'quantity_credited' => 'decimal:3',
            'unit_price' => 'decimal:2',
            'discount_percent' => 'decimal:2',
            'tax_rate' => 'decimal:2',
            'line_subtotal' => 'decimal:2',
            'line_discount' => 'decimal:2',
            'line_tax' => 'decimal:2',
            'line_total' => 'decimal:2',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function quotation(): BelongsTo
    {
        return $this->belongsTo(SalesQuotation::class, 'quotation_id');
    }
}
