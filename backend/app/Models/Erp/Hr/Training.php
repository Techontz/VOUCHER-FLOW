<?php

namespace App\Models\Erp\Hr;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Training extends HrModel
{
    public const STATUSES = ['planned', 'in_progress', 'completed', 'cancelled'];

    protected $table = 'hr_trainings';

    protected function hrCasts(): array
    {
        return ['employee_id' => 'integer', 'start_date' => 'date', 'end_date' => 'date', 'cost' => 'decimal:2'];
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }
}
