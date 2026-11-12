<?php

namespace App\Models\Erp\Hr;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** The terms a person is employed on. A new contract supersedes the old; both stay. */
class Contract extends HrModel
{
    public const STATUS_ACTIVE = 'active';

    public const STATUS_SUPERSEDED = 'superseded';

    public const STATUS_ENDED = 'ended';

    public const TYPES = ['permanent', 'fixed_term', 'probation', 'casual'];

    /** Columns that are salary data, hidden from anyone without hr.salary. */
    public const SALARY_FIELDS = ['basic_salary', 'housing_allowance', 'transport_allowance', 'other_allowance'];

    protected $table = 'hr_contracts';

    protected function hrCasts(): array
    {
        return [
            'employee_id' => 'integer',
            'created_by' => 'integer',
            'start_date' => 'date',
            'end_date' => 'date',
            'basic_salary' => 'decimal:2',
            'housing_allowance' => 'decimal:2',
            'transport_allowance' => 'decimal:2',
            'other_allowance' => 'decimal:2',
        ];
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }

    public function allowances(): float
    {
        return (float) $this->housing_allowance + (float) $this->transport_allowance + (float) $this->other_allowance;
    }
}
