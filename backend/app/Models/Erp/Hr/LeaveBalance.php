<?php

namespace App\Models\Erp\Hr;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One person's entitlement to one kind of leave in one year, and what they have taken. */
class LeaveBalance extends HrModel
{
    protected $table = 'hr_leave_balances';

    protected function hrCasts(): array
    {
        return [
            'employee_id' => 'integer',
            'leave_type_id' => 'integer',
            'year' => 'integer',
            'entitled' => 'decimal:2',
            'carried_forward' => 'decimal:2',
            'adjustment' => 'decimal:2',
            'taken' => 'decimal:2',
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
}
