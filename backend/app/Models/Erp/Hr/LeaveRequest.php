<?php

namespace App\Models\Erp\Hr;

use App\Models\User;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class LeaveRequest extends HrModel
{
    public const STATUS_PENDING = 'pending';

    public const STATUS_APPROVED = 'approved';

    public const STATUS_REJECTED = 'rejected';

    public const STATUS_CANCELLED = 'cancelled';

    protected $table = 'hr_leave_requests';

    protected function hrCasts(): array
    {
        return [
            'employee_id' => 'integer',
            'leave_type_id' => 'integer',
            'requested_by' => 'integer',
            'decided_by' => 'integer',
            'cancelled_by' => 'integer',
            'start_date' => 'date',
            'end_date' => 'date',
            'days' => 'decimal:2',
            'decided_at' => 'datetime',
            'cancelled_at' => 'datetime',
        ];
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }

    public function leaveType(): BelongsTo
    {
        return $this->belongsTo(LeaveType::class);
    }

    public function decider(): BelongsTo
    {
        return $this->belongsTo(User::class, 'decided_by');
    }

    public function requester(): BelongsTo
    {
        return $this->belongsTo(User::class, 'requested_by');
    }
}
