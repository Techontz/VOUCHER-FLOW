<?php

namespace App\Models\Erp\Hr;

use App\Models\Department;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Vacancy extends HrModel
{
    public const STATUSES = ['open', 'closed', 'filled'];

    protected $table = 'hr_vacancies';

    protected function hrCasts(): array
    {
        return ['department_id' => 'integer', 'positions' => 'integer', 'closing_date' => 'date', 'created_by' => 'integer'];
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function applicants(): HasMany
    {
        return $this->hasMany(Applicant::class);
    }
}
