<?php

namespace App\Models\Erp\Sales;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Product;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One product's price on a list, from a date (and optionally until one). */
class PriceListItem extends Model
{
    use BelongsToTenant;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer', 'price_list_id' => 'integer', 'product_id' => 'integer',
            'unit_price' => 'decimal:2', 'effective_from' => 'date', 'effective_to' => 'date',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function priceList(): BelongsTo
    {
        return $this->belongsTo(PriceList::class);
    }
}
