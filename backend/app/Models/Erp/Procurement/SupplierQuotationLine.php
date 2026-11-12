<?php

namespace App\Models\Erp\Procurement;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Tenancy comes through the parent quotation. */
class SupplierQuotationLine extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'supplier_quotation_id' => 'integer',
            'purchase_rfq_line_id' => 'integer',
            'unit_price' => 'decimal:2',
            'vat_rate' => 'decimal:2',
            'amount' => 'decimal:2',
        ];
    }

    public function rfqLine(): BelongsTo
    {
        return $this->belongsTo(PurchaseRfqLine::class, 'purchase_rfq_line_id');
    }
}
