<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One release of money against an approved voucher. A voucher may be paid in
 * several parts; each part has its own receiver, reference and signed
 * acknowledgement, and records the balance still outstanding after it.
 */
class VoucherPayment extends Model
{
    use BelongsToTenant;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'voucher_id' => 'integer',
            'paid_by_id' => 'integer',
            'sequence' => 'integer',
            'amount' => 'decimal:2',
            'balance_after' => 'decimal:2',
            'payment_date' => 'date',
            'paid_at' => 'datetime',
            'acknowledged_at' => 'datetime',
        ];
    }

    public function voucher(): BelongsTo
    {
        return $this->belongsTo(Voucher::class);
    }

    public function paidBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'paid_by_id');
    }

    /** The signed acknowledgement(s) uploaded for this payment. */
    public function acknowledgements(): HasMany
    {
        return $this->hasMany(VoucherAttachment::class)->where('document_type', VoucherAttachment::TYPE_ACKNOWLEDGEMENT);
    }

    /** "PV-2026-000083/2" — the voucher number and which payment this is. */
    public function reference(): string
    {
        return $this->voucher?->number.'/'.$this->sequence;
    }
}
