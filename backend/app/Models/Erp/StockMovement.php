<?php

namespace App\Models\Erp;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use LogicException;

/**
 * One row of the inventory ledger. Written once by the stock ledger and never
 * changed: an update or a delete is refused here, so a mistake is corrected by
 * a reversing movement that leaves both rows on the record.
 */
class StockMovement extends Model
{
    use BelongsToTenant;

    public const UPDATED_AT = null;

    protected $guarded = ['id'];

    protected static function booted(): void
    {
        static::updating(fn () => throw new LogicException('Stock movements are append-only.'));
        static::deleting(fn () => throw new LogicException('Stock movements are append-only.'));
    }

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'product_id' => 'integer',
            'warehouse_id' => 'integer',
            'stock_document_id' => 'integer',
            'quantity' => 'decimal:4',
            'unit_cost' => 'decimal:2',
            'value' => 'decimal:2',
            'balance_after' => 'decimal:4',
            'movement_date' => 'date',
            'expiry_date' => 'date',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class);
    }

    public function document(): BelongsTo
    {
        return $this->belongsTo(StockDocument::class, 'stock_document_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
