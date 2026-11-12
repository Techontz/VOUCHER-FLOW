<?php

namespace App\Models\Erp\Hr;

use App\Models\User;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** A disciplinary matter. Visible only to holders of hr.discipline. */
class DisciplineCase extends HrModel
{
    public const CATEGORIES = ['absenteeism', 'lateness', 'misconduct', 'negligence', 'insubordination', 'theft', 'safety', 'other'];

    public const ACTIONS = ['none', 'counselling', 'verbal_warning', 'written_warning', 'final_warning', 'suspension', 'dismissal'];

    protected $table = 'hr_discipline_cases';

    protected function hrCasts(): array
    {
        return [
            'employee_id' => 'integer',
            'opened_by' => 'integer',
            'closed_by' => 'integer',
            'incident_date' => 'date',
            'closed_at' => 'datetime',
        ];
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }

    public function opener(): BelongsTo
    {
        return $this->belongsTo(User::class, 'opened_by');
    }

    public function closer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'closed_by');
    }
}
