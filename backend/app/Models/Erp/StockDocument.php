<?php

namespace App\Models\Erp;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * What a person asked the stock to do: receive goods, issue them, move them,
 * correct them or count them. Nothing changes on the shelf until it is posted.
 */
class StockDocument extends Model
{
    use BelongsToTenant;

    public const TYPE_OPENING = 'opening';

    public const TYPE_GRN = 'grn';

    public const TYPE_ISSUE = 'issue';

    public const TYPE_TRANSFER = 'transfer';

    public const TYPE_ADJUSTMENT = 'adjustment';

    public const TYPE_COUNT = 'count';

    public const TYPES = [
        self::TYPE_OPENING, self::TYPE_GRN, self::TYPE_ISSUE,
        self::TYPE_TRANSFER, self::TYPE_ADJUSTMENT, self::TYPE_COUNT,
    ];

    /** The prefix each type's numbers carry. */
    public const PREFIXES = [
        self::TYPE_OPENING => 'OPN',
        self::TYPE_GRN => 'GRN',
        self::TYPE_ISSUE => 'ISS',
        self::TYPE_TRANSFER => 'TRF',
        self::TYPE_ADJUSTMENT => 'ADJ',
        self::TYPE_COUNT => 'CNT',
    ];

    public const STATUS_DRAFT = 'draft';

    public const STATUS_POSTED = 'posted';

    public const STATUS_CANCELLED = 'cancelled';

    public const STATUS_REVERSED = 'reversed';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'warehouse_id' => 'integer',
            'to_warehouse_id' => 'integer',
            'supplier_id' => 'integer',
            'reversal_of_id' => 'integer',
            'created_by' => 'integer',
            'posted_by' => 'integer',
            'document_date' => 'date',
            'posted_at' => 'datetime',
        ];
    }

    public function isDraft(): bool
    {
        return $this->status === self::STATUS_DRAFT;
    }

    public function lines(): HasMany
    {
        return $this->hasMany(StockDocumentLine::class);
    }

    public function movements(): HasMany
    {
        return $this->hasMany(StockMovement::class);
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class);
    }

    public function toWarehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class, 'to_warehouse_id');
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function poster(): BelongsTo
    {
        return $this->belongsTo(User::class, 'posted_by');
    }

    public function reversalOf(): BelongsTo
    {
        return $this->belongsTo(self::class, 'reversal_of_id');
    }
}
