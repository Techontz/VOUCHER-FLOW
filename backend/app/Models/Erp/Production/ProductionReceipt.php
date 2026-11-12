<?php

namespace App\Models\Erp\Production;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\StockDocument;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

/**
 * Output recorded against an order. It waits for a quality check: only a
 * released receipt puts its good quantity into stock.
 */
class ProductionReceipt extends Model
{
    use BelongsToTenant;

    public const STATUS_PENDING = 'pending_qc';

    public const STATUS_RELEASED = 'released';

    public const STATUS_REJECTED = 'rejected';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'production_order_id' => 'integer',
            'stock_document_id' => 'integer',
            'receipt_date' => 'date',
            'expiry_date' => 'date',
            'produced_quantity' => 'decimal:3',
            'good_quantity' => 'decimal:3',
            'rejected_quantity' => 'decimal:3',
            'wastage_quantity' => 'decimal:3',
            'released_quantity' => 'decimal:3',
            'conversion_cost' => 'decimal:2',
            'unit_cost' => 'decimal:2',
            'value' => 'decimal:2',
            'is_final' => 'boolean',
        ];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(ProductionOrder::class, 'production_order_id');
    }

    public function qc(): HasOne
    {
        return $this->hasOne(QcCheck::class);
    }

    public function stockDocument(): BelongsTo
    {
        return $this->belongsTo(StockDocument::class);
    }

    public function recorder(): BelongsTo
    {
        return $this->belongsTo(User::class, 'recorded_by');
    }
}
