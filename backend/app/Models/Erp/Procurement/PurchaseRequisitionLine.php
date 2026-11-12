<?php

namespace App\Models\Erp\Procurement;

use App\Models\Erp\Account;
use App\Models\Erp\Product;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Tenancy comes through the parent requisition, which is always resolved first. */
class PurchaseRequisitionLine extends Model
{
    public const TYPE_STOCK = 'stock';

    public const TYPE_SERVICE = 'service';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'purchase_requisition_id' => 'integer',
            'product_id' => 'integer',
            'expense_account_id' => 'integer',
            'quantity' => 'decimal:3',
            'estimated_unit_price' => 'decimal:2',
            'amount' => 'decimal:2',
        ];
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
