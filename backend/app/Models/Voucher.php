<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Voucher extends Model
{
    use BelongsToTenant, HasFactory, SoftDeletes;

    public const STATUS_DRAFT = 'draft';

    public const STATUS_IN_REVIEW = 'in_review';

    public const STATUS_CHANGES_REQUESTED = 'changes_requested';

    public const STATUS_APPROVED = 'approved';

    public const STATUS_REJECTED = 'rejected';

    public const STATUS_CANCELLED = 'cancelled';

    /** Money has actually left the account. The end of the lifecycle. */
    public const STATUS_PAID = 'paid';

    /** Settles into a bank account, reconciled against a statement. */
    public const KIND_BANK = 'bank';

    /** Comes out of a petty cash float, acknowledged by hand on the day. */
    public const KIND_CASH = 'cash';

    public const KINDS = [self::KIND_BANK, self::KIND_CASH];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'voucher_date' => 'date',
            'step_signed_at' => 'datetime',
            'submitted_at' => 'datetime',
            'approved_at' => 'datetime',
            'rejected_at' => 'datetime',
            'paid_at' => 'datetime',
            'payment_date' => 'date',
        ];
    }

    public function voucherType(): BelongsTo
    {
        return $this->belongsTo(VoucherType::class);
    }

    public function workflow(): BelongsTo
    {
        return $this->belongsTo(Workflow::class);
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function requester(): BelongsTo
    {
        return $this->belongsTo(User::class, 'requester_id');
    }

    public function paidBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'paid_by_id');
    }

    public function approvals(): HasMany
    {
        return $this->hasMany(VoucherApproval::class)->orderBy('acted_at')->orderBy('id');
    }

    public function attachments(): HasMany
    {
        return $this->hasMany(VoucherAttachment::class);
    }

    public function comments(): HasMany
    {
        return $this->hasMany(VoucherComment::class)->orderBy('created_at');
    }

    public function isEditable(): bool
    {
        return in_array($this->status, [self::STATUS_DRAFT, self::STATUS_CHANGES_REQUESTED], true);
    }

    public function isTerminal(): bool
    {
        return in_array($this->status, [
            self::STATUS_REJECTED, self::STATUS_CANCELLED, self::STATUS_PAID,
        ], true);
    }

    /** Approved, and the money has not moved yet: the cashier's queue. */
    public function isAwaitingPayment(): bool
    {
        return $this->status === self::STATUS_APPROVED && $this->paid_at === null;
    }

    public function isPaid(): bool
    {
        return $this->status === self::STATUS_PAID;
    }

    public function isBank(): bool
    {
        return $this->kind === self::KIND_BANK;
    }

    public function scopeAwaitingPayment(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_APPROVED)->whereNull('paid_at');
    }

    public function scopeKind(Builder $query, ?string $kind): Builder
    {
        return in_array($kind, self::KINDS, true) ? $query->where('kind', $kind) : $query;
    }

    /** True when the current step's actor has signed but not yet submitted onward. */
    public function isSignedAtCurrentStep(): bool
    {
        return $this->status === self::STATUS_IN_REVIEW && $this->step_signed_at !== null;
    }

    public function currentStep(): ?WorkflowStep
    {
        if ($this->status !== self::STATUS_IN_REVIEW || ! $this->current_step_position) {
            return null;
        }

        return $this->workflow?->steps->firstWhere('position', $this->current_step_position);
    }

    public function scopeStatus(Builder $query, ?string $status): Builder
    {
        if (! $status || $status === 'all') {
            return $query;
        }

        return match ($status) {
            'pending' => $query->where('status', self::STATUS_IN_REVIEW),
            'drafts' => $query->where('status', self::STATUS_DRAFT),
            default => $query->where('status', $status),
        };
    }

    public function scopeSearch(Builder $query, ?string $term): Builder
    {
        $term = trim((string) $term);

        if (mb_strlen($term) < 2) {
            return $query;
        }

        $like = '%'.$term.'%';

        return $query->where(function (Builder $q) use ($like) {
            $q->where('number', 'like', $like)
                ->orWhere('purpose', 'like', $like)
                ->orWhere('payee', 'like', $like)
                ->orWhere('description', 'like', $like)
                ->orWhere('account_ref', 'like', $like)
                ->orWhere('amount', 'like', $like)
                ->orWhereHas('requester', fn (Builder $r) => $r->where('name', 'like', $like));
        });
    }
}
