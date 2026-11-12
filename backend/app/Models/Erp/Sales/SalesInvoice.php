<?php

namespace App\Models\Erp\Sales;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Customer;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A bill to a customer. Posting puts it on the books once:
 * Dr Accounts receivable, Cr Sales revenue and Cr VAT payable.
 */
class SalesInvoice extends Model
{
    use BelongsToTenant;

    public const STATUS_DRAFT = 'draft';

    public const STATUS_POSTED = 'posted';

    public const STATUS_CANCELLED = 'cancelled';

    protected $guarded = ['id'];

    protected $appends = ['balance'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer', 'customer_id' => 'integer', 'sales_order_id' => 'integer', 'loading_order_id' => 'integer',
            'invoice_date' => 'date', 'due_date' => 'date', 'posted_at' => 'datetime',
            'subtotal' => 'decimal:2', 'discount_total' => 'decimal:2', 'tax_total' => 'decimal:2', 'total' => 'decimal:2',
            'amount_paid' => 'decimal:2', 'amount_credited' => 'decimal:2',
        ];
    }

    /** What the customer still owes on this invoice. */
    public function getBalanceAttribute(): float
    {
        return round((float) $this->total - (float) $this->amount_paid - (float) $this->amount_credited, 2);
    }

    public function lines(): HasMany
    {
        return $this->hasMany(SalesInvoiceLine::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class)->withTrashed();
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(SalesOrder::class, 'sales_order_id');
    }

    public function loadingOrder(): BelongsTo
    {
        return $this->belongsTo(LoadingOrder::class);
    }

    public function allocations(): HasMany
    {
        return $this->hasMany(SalesReceiptAllocation::class);
    }

    public function creditNotes(): HasMany
    {
        return $this->hasMany(SalesCreditNote::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function poster(): BelongsTo
    {
        return $this->belongsTo(User::class, 'posted_by');
    }
}
