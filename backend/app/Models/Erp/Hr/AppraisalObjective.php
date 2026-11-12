<?php

namespace App\Models\Erp\Hr;

class AppraisalObjective extends HrModel
{
    protected $table = 'hr_appraisal_objectives';

    protected function hrCasts(): array
    {
        return ['appraisal_id' => 'integer', 'weight' => 'integer', 'rating' => 'integer'];
    }
}
