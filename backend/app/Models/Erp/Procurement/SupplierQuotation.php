<?php

namespace App\Models\Erp\Procurement;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Supplier;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A supplier's priced answer to an RFQ. */
class SupplierQuotation extends Model
{
    use BelongsToTenant;

    public const STATUS_RECEIVED = 'received';

    public const STATUS_SELECTED = 'selected';

    public const STATUS_NOT_SELECTED = 'not_selected';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'purchase_rfq_id' => 'integer',
            'supplier_id' => 'integer',
            'created_by' => 'integer',
            'lead_time_days' => 'integer',
            'quotation_date' => 'date',
            'valid_until' => 'date',
            'subtotal' => 'decimal:2',
            'vat_amount' => 'decimal:2',
            'total' => 'decimal:2',
        ];
    }

    public function lines(): HasMany
    {
        return $this->hasMany(SupplierQuotationLine::class);
    }

    public function rfq(): BelongsTo
    {
        return $this->belongsTo(PurchaseRfq::class, 'purchase_rfq_id');
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class)->withTrashed();
    }
}
