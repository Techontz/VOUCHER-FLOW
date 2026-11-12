<?php

namespace App\Models\Erp\Procurement;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Tenancy comes through the parent payment. */
class SupplierPaymentAllocation extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'supplier_payment_id' => 'integer',
            'supplier_invoice_id' => 'integer',
            'amount' => 'decimal:2',
        ];
    }

    public function payment(): BelongsTo
    {
        return $this->belongsTo(SupplierPayment::class, 'supplier_payment_id');
    }

    public function invoice(): BelongsTo
    {
        return $this->belongsTo(SupplierInvoice::class, 'supplier_invoice_id');
    }
}
