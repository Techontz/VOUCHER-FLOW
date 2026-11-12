<?php

namespace App\Models\Erp\Procurement;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\JournalEntry;
use App\Models\Erp\Supplier;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A supplier's bill, matched against its order and what was received. Posted
 * once; a variance beyond tolerance waits for an approver first.
 */
class SupplierInvoice extends Model
{
    use BelongsToTenant;

    public const STATUS_DRAFT = 'draft';

    public const STATUS_AWAITING_APPROVAL = 'awaiting_approval';

    public const STATUS_APPROVED = 'approved';

    public const STATUS_POSTED = 'posted';

    public const STATUS_CANCELLED = 'cancelled';

    public const MATCHED = 'matched';

    public const VARIANCE = 'variance';

    protected $guarded = ['id'];

    protected $appends = ['outstanding', 'payment_status'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'supplier_id' => 'integer',
            'purchase_order_id' => 'integer',
            'created_by' => 'integer',
            'posted_by' => 'integer',
            'variance_approved_by' => 'integer',
            'journal_entry_id' => 'integer',
            'invoice_date' => 'date',
            'due_date' => 'date',
            'subtotal' => 'decimal:2',
            'vat_amount' => 'decimal:2',
            'total' => 'decimal:2',
            'amount_paid' => 'decimal:2',
            'posted_at' => 'datetime',
            'variance_approved_at' => 'datetime',
        ];
    }

    public function getOutstandingAttribute(): float
    {
        return $this->status === self::STATUS_POSTED ? round((float) $this->total - (float) $this->amount_paid, 2) : 0.0;
    }

    public function getPaymentStatusAttribute(): ?string
    {
        if ($this->status !== self::STATUS_POSTED) {
            return null;
        }

        $outstanding = $this->outstanding;

        return $outstanding <= 0.004 ? 'paid' : ((float) $this->amount_paid > 0 ? 'partially_paid' : 'unpaid');
    }

    public function lines(): HasMany
    {
        return $this->hasMany(SupplierInvoiceLine::class);
    }

    public function approvals(): HasMany
    {
        return $this->hasMany(ProcurementApproval::class, 'approvable_id')
            ->where('approvable_type', class_basename(self::class))->orderBy('id');
    }

    public function allocations(): HasMany
    {
        return $this->hasMany(SupplierPaymentAllocation::class);
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class)->withTrashed();
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(PurchaseOrder::class, 'purchase_order_id');
    }

    public function journal(): BelongsTo
    {
        return $this->belongsTo(JournalEntry::class, 'journal_entry_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function poster(): BelongsTo
    {
        return $this->belongsTo(User::class, 'posted_by');
    }

    public function varianceApprover(): BelongsTo
    {
        return $this->belongsTo(User::class, 'variance_approved_by');
    }
}
