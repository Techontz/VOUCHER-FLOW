<?php

namespace App\Models\Erp\Sales;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Account;
use App\Models\Erp\Customer;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Money received from a customer. Recorded by one person, verified by
 * another; only verification posts it (Dr cash or bank, Cr receivable).
 */
class SalesReceipt extends Model
{
    use BelongsToTenant;

    public const STATUS_RECORDED = 'recorded';

    public const STATUS_VERIFIED = 'verified';

    public const STATUS_REJECTED = 'rejected';

    public const METHODS = ['cash', 'bank_transfer', 'mobile_money', 'cheque'];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer', 'customer_id' => 'integer', 'account_id' => 'integer',
            'receipt_date' => 'date', 'verified_at' => 'datetime', 'amount' => 'decimal:2',
            'created_by' => 'integer', 'verified_by' => 'integer',
        ];
    }

    public function allocations(): HasMany
    {
        return $this->hasMany(SalesReceiptAllocation::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class)->withTrashed();
    }

    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function verifier(): BelongsTo
    {
        return $this->belongsTo(User::class, 'verified_by');
    }
}
