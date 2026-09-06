<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class WorkflowStep extends Model
{
    use HasFactory;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'can_sign' => 'boolean',
            'can_approve' => 'boolean',
            'can_reject' => 'boolean',
            'can_request_changes' => 'boolean',
            'can_print' => 'boolean',
            'can_download' => 'boolean',
            'requires_signature' => 'boolean',
            'min_amount' => 'decimal:2',
            'max_amount' => 'decimal:2',
        ];
    }

    public function workflow(): BelongsTo
    {
        return $this->belongsTo(Workflow::class);
    }

    public function assignedUser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_user_id');
    }

    public static function roleLabel(string $role): string
    {
        return match ($role) {
            'employee' => 'Employee',
            'hod' => 'HOD',
            'manager' => 'Manager',
            'finance' => 'Finance',
            'director' => 'Director',
            default => 'Custom approver',
        };
    }

    /** The originating step: the requester's own, never an approval gate. */
    public function isRequestStep(): bool
    {
        return $this->position === 1 || $this->role === 'employee';
    }

    /** Whether this step applies to a given amount (amount-threshold routing). */
    public function appliesToAmount(float $amount): bool
    {
        if ($this->min_amount !== null && $amount < (float) $this->min_amount) {
            return false;
        }

        if ($this->max_amount !== null && $amount > (float) $this->max_amount) {
            return false;
        }

        return true;
    }

    public function capabilities(): array
    {
        return [
            'sign' => $this->can_sign,
            'approve' => $this->can_approve,
            'reject' => $this->can_reject,
            'request_changes' => $this->can_request_changes,
            'print' => $this->can_print,
            'download' => $this->can_download,
        ];
    }

    public function label(string $locale = 'en'): string
    {
        return $locale === 'sw' && $this->name_sw ? $this->name_sw : $this->name;
    }
}
