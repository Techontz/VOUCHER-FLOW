<?php

namespace App\Models\Erp\Procurement;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Supplier;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A request for quotation sent to several suppliers, and the one chosen. */
class PurchaseRfq extends Model
{
    use BelongsToTenant;

    public const STATUS_DRAFT = 'draft';

    public const STATUS_SENT = 'sent';

    public const STATUS_AWARDED = 'awarded';

    public const STATUS_CANCELLED = 'cancelled';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'purchase_requisition_id' => 'integer',
            'selected_quotation_id' => 'integer',
            'awarded_by' => 'integer',
            'created_by' => 'integer',
            'issue_date' => 'date',
            'closing_date' => 'date',
            'awarded_at' => 'datetime',
        ];
    }

    public function lines(): HasMany
    {
        return $this->hasMany(PurchaseRfqLine::class);
    }

    public function suppliers(): BelongsToMany
    {
        return $this->belongsToMany(Supplier::class, 'purchase_rfq_suppliers')->withTimestamps();
    }

    public function quotations(): HasMany
    {
        return $this->hasMany(SupplierQuotation::class);
    }

    public function requisition(): BelongsTo
    {
        return $this->belongsTo(PurchaseRequisition::class, 'purchase_requisition_id');
    }

    public function selectedQuotation(): BelongsTo
    {
        return $this->belongsTo(SupplierQuotation::class, 'selected_quotation_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function awarder(): BelongsTo
    {
        return $this->belongsTo(User::class, 'awarded_by');
    }
}
