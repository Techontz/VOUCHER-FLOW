<?php

namespace App\Models\Erp\Sales;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Customer;
use App\Models\Erp\StockDocument;
use App\Models\Erp\Warehouse;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * What one truck takes from one warehouse for one order.
 *
 *   open → loaded (storekeeper confirms: stock leaves, once) → dispatched (gate pass) → delivered (proof of delivery)
 *
 * The fleet module links trips here polymorphically (source_type 'loading_order').
 */
class LoadingOrder extends Model
{
    use BelongsToTenant;

    public const SOURCE_TYPE = 'loading_order';

    public const STATUS_OPEN = 'open';

    public const STATUS_LOADED = 'loaded';

    public const STATUS_DISPATCHED = 'dispatched';

    public const STATUS_DELIVERED = 'delivered';

    public const STATUS_CANCELLED = 'cancelled';

    public const STATUSES = [self::STATUS_OPEN, self::STATUS_LOADED, self::STATUS_DISPATCHED, self::STATUS_DELIVERED, self::STATUS_CANCELLED];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer', 'sales_order_id' => 'integer', 'customer_id' => 'integer', 'warehouse_id' => 'integer',
            'vehicle_id' => 'integer', 'driver_user_id' => 'integer', 'stock_document_id' => 'integer', 'return_document_id' => 'integer',
            'planned_date' => 'date', 'received_date' => 'date',
            'loaded_at' => 'datetime', 'driver_confirmed_at' => 'datetime', 'security_confirmed_at' => 'datetime',
            'delivery_note_issued_at' => 'datetime', 'gate_pass_issued_at' => 'datetime', 'pod_recorded_at' => 'datetime',
            'discrepancy_resolved_at' => 'datetime',
        ];
    }

    public function lines(): HasMany
    {
        return $this->hasMany(LoadingOrderLine::class);
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(SalesOrder::class, 'sales_order_id');
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class)->withTrashed();
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class);
    }

    public function stockDocument(): BelongsTo
    {
        return $this->belongsTo(StockDocument::class);
    }

    public function returnDocument(): BelongsTo
    {
        return $this->belongsTo(StockDocument::class, 'return_document_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function loader(): BelongsTo
    {
        return $this->belongsTo(User::class, 'loaded_by');
    }

    public function driverConfirmer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'driver_confirmed_by');
    }

    public function securityConfirmer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'security_confirmed_by');
    }

    public function gatePassIssuer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'gate_pass_issued_by');
    }

    public function podRecorder(): BelongsTo
    {
        return $this->belongsTo(User::class, 'pod_recorded_by');
    }

    public function resolver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'discrepancy_resolved_by');
    }
}
