<?php

namespace App\Models\Erp\Hr;

use Illuminate\Database\Eloquent\Relations\HasMany;

class AppraisalPeriod extends HrModel
{
    protected $table = 'hr_appraisal_periods';

    protected function hrCasts(): array
    {
        return ['start_date' => 'date', 'end_date' => 'date'];
    }

    public function appraisals(): HasMany
    {
        return $this->hasMany(Appraisal::class, 'period_id');
    }
}
