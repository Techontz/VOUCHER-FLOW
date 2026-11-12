<?php

namespace App\Models\Erp\Sales;

use App\Models\Erp\Product;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Ordered, approved, loaded and received: four quantities, four columns. */
class LoadingOrderLine extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'loading_order_id' => 'integer', 'sales_order_line_id' => 'integer', 'product_id' => 'integer',
            'quantity_ordered' => 'decimal:3', 'quantity_approved' => 'decimal:3',
            'quantity_loaded' => 'decimal:3', 'quantity_received' => 'decimal:3',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function orderLine(): BelongsTo
    {
        return $this->belongsTo(SalesOrderLine::class, 'sales_order_line_id');
    }

    public function loadingOrder(): BelongsTo
    {
        return $this->belongsTo(LoadingOrder::class);
    }
}
