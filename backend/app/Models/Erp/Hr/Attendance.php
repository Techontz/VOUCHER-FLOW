<?php

namespace App\Models\Erp\Hr;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One person's day: when they came, when they left, and what it counts as. */
class Attendance extends HrModel
{
    public const STATUSES = ['present', 'late', 'absent', 'leave', 'off'];

    protected $table = 'hr_attendance';

    protected function hrCasts(): array
    {
        return [
            'employee_id' => 'integer',
            'recorded_by' => 'integer',
            'date' => 'date',
            'hours_worked' => 'decimal:2',
            'overtime_hours' => 'decimal:2',
        ];
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }
}
