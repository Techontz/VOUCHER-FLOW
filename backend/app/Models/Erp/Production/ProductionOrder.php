<?php

namespace App\Models\Erp\Production;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Product;
use App\Models\Erp\StockDocument;
use App\Models\Erp\Warehouse;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One production run, from plan to close. Its materials and output move
 * through stock documents that name it as their source; the cost columns are
 * running totals the production service keeps alongside those postings.
 */
class ProductionOrder extends Model
{
    use BelongsToTenant;

    /** What stock documents raised by an order record as their source_type. */
    public const SOURCE = 'production_order';

    public const STATUS_PLANNED = 'planned';

    public const STATUS_RELEASED = 'released';

    public const STATUS_IN_PROGRESS = 'in_progress';

    public const STATUS_COMPLETED = 'completed';

    public const STATUS_CLOSED = 'closed';

    public const STATUS_CANCELLED = 'cancelled';

    public const STATUSES = [
        self::STATUS_PLANNED, self::STATUS_RELEASED, self::STATUS_IN_PROGRESS,
        self::STATUS_COMPLETED, self::STATUS_CLOSED, self::STATUS_CANCELLED,
    ];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'product_id' => 'integer',
            'bom_id' => 'integer',
            'materials_warehouse_id' => 'integer',
            'output_warehouse_id' => 'integer',
            'planned_quantity' => 'decimal:3',
            'planned_start' => 'date',
            'planned_end' => 'date',
            'standard_unit_cost' => 'decimal:4',
            'produced_quantity' => 'decimal:3',
            'good_quantity' => 'decimal:3',
            'released_quantity' => 'decimal:3',
            'rejected_quantity' => 'decimal:3',
            'wastage_quantity' => 'decimal:3',
            'material_cost' => 'decimal:2',
            'conversion_cost' => 'decimal:2',
            'received_value' => 'decimal:2',
            'variance_value' => 'decimal:2',
            'released_at' => 'datetime',
            'started_at' => 'datetime',
            'completed_at' => 'datetime',
            'closed_at' => 'datetime',
            'cancelled_at' => 'datetime',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function bom(): BelongsTo
    {
        return $this->belongsTo(Bom::class);
    }

    public function materialsWarehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class, 'materials_warehouse_id');
    }

    public function outputWarehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class, 'output_warehouse_id');
    }

    public function receipts(): HasMany
    {
        return $this->hasMany(ProductionReceipt::class)->orderBy('id');
    }

    public function qcChecks(): HasMany
    {
        return $this->hasMany(QcCheck::class);
    }

    /** Every stock document this order raised: material issues and output receipts. */
    public function stockDocuments(): HasMany
    {
        return $this->hasMany(StockDocument::class, 'source_id')->where('source_type', self::SOURCE);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function releaser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'released_by');
    }

    public function completer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'completed_by');
    }

    public function closer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'closed_by');
    }

    public function canceller(): BelongsTo
    {
        return $this->belongsTo(User::class, 'cancelled_by');
    }

    /** Orders still on the floor. */
    public function scopeOpen(Builder $query): Builder
    {
        return $query->whereIn('status', [self::STATUS_RELEASED, self::STATUS_IN_PROGRESS]);
    }

    /** What the order has cost so far and not yet passed on to finished stock. */
    public function wipBalance(): float
    {
        return round((float) $this->material_cost + (float) $this->conversion_cost - (float) $this->received_value, 2);
    }
}
