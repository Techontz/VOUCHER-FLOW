<?php

namespace App\Models\Erp\Hr;

use App\Models\Department;
use App\Models\User;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** A transfer, promotion or change of title, kept as history. */
class Movement extends HrModel
{
    public const TYPES = ['transfer', 'promotion', 'demotion', 'redesignation'];

    protected $table = 'hr_movements';

    protected function hrCasts(): array
    {
        return [
            'employee_id' => 'integer',
            'from_department_id' => 'integer',
            'to_department_id' => 'integer',
            'created_by' => 'integer',
            'effective_date' => 'date',
        ];
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }

    public function fromDepartment(): BelongsTo
    {
        return $this->belongsTo(Department::class, 'from_department_id');
    }

    public function toDepartment(): BelongsTo
    {
        return $this->belongsTo(Department::class, 'to_department_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
