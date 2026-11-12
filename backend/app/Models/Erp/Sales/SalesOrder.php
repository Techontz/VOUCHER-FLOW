<?php

namespace App\Models\Erp\Sales;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Customer;
use App\Models\Erp\Warehouse;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A customer's order, from draft to delivered.
 *
 *   draft → submitted → (approved) awaiting_payment | ready → loading → dispatched → delivered
 *
 * A prepayment order waits in awaiting_payment until finance verifies a
 * payment covering it; a credit order is ready as soon as it is approved
 * within the credit policy.
 */
class SalesOrder extends Model
{
    use BelongsToTenant;

    public const STATUS_DRAFT = 'draft';

    public const STATUS_SUBMITTED = 'submitted';

    public const STATUS_AWAITING_PAYMENT = 'awaiting_payment';

    public const STATUS_READY = 'ready';

    public const STATUS_LOADING = 'loading';

    public const STATUS_DISPATCHED = 'dispatched';

    public const STATUS_DELIVERED = 'delivered';

    public const STATUS_REJECTED = 'rejected';

    public const STATUS_CANCELLED = 'cancelled';

    public const STATUSES = [
        self::STATUS_DRAFT, self::STATUS_SUBMITTED, self::STATUS_AWAITING_PAYMENT, self::STATUS_READY,
        self::STATUS_LOADING, self::STATUS_DISPATCHED, self::STATUS_DELIVERED, self::STATUS_REJECTED, self::STATUS_CANCELLED,
    ];

    /** Approved and not yet finished: the order still counts against the customer's credit. */
    public const OPEN = [self::STATUS_AWAITING_PAYMENT, self::STATUS_READY, self::STATUS_LOADING, self::STATUS_DISPATCHED];

    public const MODE_PREPAYMENT = 'prepayment';

    public const MODE_CREDIT = 'credit';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer', 'customer_id' => 'integer', 'quotation_id' => 'integer', 'warehouse_id' => 'integer',
            'order_date' => 'date', 'required_date' => 'date',
            'subtotal' => 'decimal:2', 'discount_total' => 'decimal:2', 'tax_total' => 'decimal:2', 'total' => 'decimal:2',
            'policy_check' => 'array',
            'submitted_at' => 'datetime', 'approved_at' => 'datetime', 'payment_verified_at' => 'datetime',
        ];
    }

    public function lines(): HasMany
    {
        return $this->hasMany(SalesOrderLine::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class)->withTrashed();
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class);
    }

    public function quotation(): BelongsTo
    {
        return $this->belongsTo(SalesQuotation::class);
    }

    public function invoices(): HasMany
    {
        return $this->hasMany(SalesInvoice::class);
    }

    public function loadingOrders(): HasMany
    {
        return $this->hasMany(LoadingOrder::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function approver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'approved_by');
    }

    public function overrider(): BelongsTo
    {
        return $this->belongsTo(User::class, 'overridden_by');
    }
}
