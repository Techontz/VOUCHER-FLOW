<?php

namespace App\Models\Erp;

use App\Models\Concerns\BelongsToTenant;
use App\Services\Erp\StockLedger;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** The running total the ledger maintains. Only {@see StockLedger} writes it. */
class StockBalance extends Model
{
    use BelongsToTenant;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'product_id' => 'integer',
            'warehouse_id' => 'integer',
            'quantity' => 'decimal:4',
            'average_cost' => 'decimal:4',
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
}
