<?php

namespace App\Models\Erp\Procurement;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Tenancy comes through the parent receipt. */
class PurchaseReceiptLine extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'purchase_receipt_id' => 'integer',
            'purchase_order_line_id' => 'integer',
            'stock_document_line_id' => 'integer',
            'quantity' => 'decimal:3',
            'unit_cost' => 'decimal:2',
            'value' => 'decimal:2',
        ];
    }

    public function orderLine(): BelongsTo
    {
        return $this->belongsTo(PurchaseOrderLine::class, 'purchase_order_line_id');
    }
}
