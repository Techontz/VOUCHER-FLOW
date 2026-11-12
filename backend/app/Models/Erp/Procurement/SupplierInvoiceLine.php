<?php

namespace App\Models\Erp\Procurement;

use App\Models\Erp\Account;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Tenancy comes through the parent invoice. */
class SupplierInvoiceLine extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'supplier_invoice_id' => 'integer',
            'purchase_order_line_id' => 'integer',
            'expense_account_id' => 'integer',
            'quantity' => 'decimal:3',
            'unit_price' => 'decimal:2',
            'vat_rate' => 'decimal:2',
            'amount' => 'decimal:2',
            'vat_amount' => 'decimal:2',
            'order_unit_price' => 'decimal:2',
            'matchable_quantity' => 'decimal:3',
            'price_variance' => 'decimal:2',
            'quantity_variance' => 'decimal:3',
            'flagged' => 'boolean',
        ];
    }

    public function orderLine(): BelongsTo
    {
        return $this->belongsTo(PurchaseOrderLine::class, 'purchase_order_line_id');
    }

    public function expenseAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'expense_account_id');
    }
}
