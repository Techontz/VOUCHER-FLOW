<?php

namespace App\Models\Erp\Procurement;

use App\Models\Erp\Product;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Tenancy comes through the parent RFQ. */
class PurchaseRfqLine extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'purchase_rfq_id' => 'integer',
            'purchase_requisition_line_id' => 'integer',
            'product_id' => 'integer',
            'expense_account_id' => 'integer',
            'quantity' => 'decimal:3',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
