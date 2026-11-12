<?php

namespace App\Models\Erp\Sales;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** The part of a receipt applied to one invoice. */
class SalesReceiptAllocation extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return ['sales_receipt_id' => 'integer', 'sales_invoice_id' => 'integer', 'amount' => 'decimal:2'];
    }

    public function receipt(): BelongsTo
    {
        return $this->belongsTo(SalesReceipt::class, 'sales_receipt_id');
    }

    public function invoice(): BelongsTo
    {
        return $this->belongsTo(SalesInvoice::class, 'sales_invoice_id');
    }
}
