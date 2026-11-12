<?php

namespace App\Models\Erp\Procurement;

use App\Models\Erp\Account;
use App\Models\Erp\Product;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Tenancy comes through the parent order. */
class PurchaseOrderLine extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'purchase_order_id' => 'integer',
            'purchase_requisition_line_id' => 'integer',
            'product_id' => 'integer',
            'expense_account_id' => 'integer',
            'quantity' => 'decimal:3',
            'unit_price' => 'decimal:2',
            'vat_rate' => 'decimal:2',
            'amount' => 'decimal:2',
            'vat_amount' => 'decimal:2',
            'received_quantity' => 'decimal:3',
            'invoiced_quantity' => 'decimal:3',
        ];
    }

    public function isService(): bool
    {
        return $this->line_type === PurchaseRequisitionLine::TYPE_SERVICE;
    }

    public function outstanding(): float
    {
        return round((float) $this->quantity - (float) $this->received_quantity, 3);
    }

    /** Received (or confirmed) and not yet invoiced: what an invoice can match against. */
    public function matchable(): float
    {
        return round((float) $this->received_quantity - (float) $this->invoiced_quantity, 3);
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(PurchaseOrder::class, 'purchase_order_id');
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function expenseAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'expense_account_id');
    }
}
