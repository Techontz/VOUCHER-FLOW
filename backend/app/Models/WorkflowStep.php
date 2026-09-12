<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class WorkflowStep extends Model
{
    use HasFactory;

    protected $guarded = ['id'];

    /**
     * What a step may be configured to do. A company admin composes a workflow
     * out of these, which is what lets one tenant run Employee → Supervisor →
     * Manager → Finance while another runs Employee → HOD → CEO → Cashier.
     */
    public const CAPABILITIES = [
        'sign', 'approve', 'reject', 'request_changes', 'print', 'download', 'pay',
    ];

    /** Roles a step may be pinned to. 'custom' means "whoever is named below". */
    public const ROLES = [
        'employee', 'hod', 'ceo', 'manager', 'cashier', 'finance', 'director', 'custom',
    ];

    protected function casts(): array
    {
        return [
            /*
             * Integer columns are cast because they are compared with === in
             * PHP. MySQL returns them as strings under emulated prepared
             * statements, where "8" === 8 is false — which silently turned an
             * owner into a stranger and a matching id into a mismatch.
             */
            'workflow_id' => 'integer',
            'position' => 'integer',
            'assigned_user_id' => 'integer',
            'can_sign' => 'boolean',
            'can_approve' => 'boolean',
            'can_reject' => 'boolean',
            'can_request_changes' => 'boolean',
            'can_print' => 'boolean',
            'can_download' => 'boolean',
            'can_pay' => 'boolean',
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
            'ceo' => 'CEO / Manager',
            'manager' => 'Manager',
            'cashier' => 'Cashier',
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

    /**
     * A step that exists to release money rather than to decide anything.
     *
     * It sits outside the approval chain: the chain ends when the last step
     * that can actually approve has approved, and the voucher becomes payable.
     * A step that both approves and pays (a one-person company, say) is still
     * an approval step — it is only the pay-only steps that stand apart.
     */
    public function isPaymentStep(): bool
    {
        return $this->can_pay && ! $this->can_approve;
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
            'pay' => $this->can_pay,
        ];
    }

    public function label(string $locale = 'en'): string
    {
        return $locale === 'sw' && $this->name_sw ? $this->name_sw : $this->name;
    }
}
