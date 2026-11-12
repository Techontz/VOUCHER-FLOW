<?php

namespace App\Models\Erp\Procurement;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Department;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A department asking to buy something, before anyone talks to a supplier. */
class PurchaseRequisition extends Model
{
    use BelongsToTenant;

    public const STATUS_DRAFT = 'draft';

    public const STATUS_SUBMITTED = 'submitted';

    public const STATUS_APPROVED = 'approved';

    public const STATUS_REJECTED = 'rejected';

    public const STATUS_ORDERED = 'ordered';

    public const STATUS_CANCELLED = 'cancelled';

    public const STATUSES = [
        self::STATUS_DRAFT, self::STATUS_SUBMITTED, self::STATUS_APPROVED,
        self::STATUS_REJECTED, self::STATUS_ORDERED, self::STATUS_CANCELLED,
    ];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'department_id' => 'integer',
            'requested_by' => 'integer',
            'needed_by' => 'date',
            'total' => 'decimal:2',
            'approvals_required' => 'integer',
            'submitted_at' => 'datetime',
            'approved_at' => 'datetime',
            'rejected_at' => 'datetime',
            'cancelled_at' => 'datetime',
        ];
    }

    public function lines(): HasMany
    {
        return $this->hasMany(PurchaseRequisitionLine::class);
    }

    public function approvals(): HasMany
    {
        return $this->hasMany(ProcurementApproval::class, 'approvable_id')
            ->where('approvable_type', class_basename(self::class))->orderBy('id');
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function requester(): BelongsTo
    {
        return $this->belongsTo(User::class, 'requested_by');
    }

    public function orders(): HasMany
    {
        return $this->hasMany(PurchaseOrder::class);
    }
}
