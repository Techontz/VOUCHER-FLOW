<?php

namespace App\Models\Erp\Hr;

class Shift extends HrModel
{
    protected $table = 'hr_shifts';

    protected function hrCasts(): array
    {
        return ['grace_minutes' => 'integer', 'is_default' => 'boolean'];
    }

    /** Scheduled hours, overnight shifts included. */
    public function hours(): float
    {
        $start = strtotime('1970-01-01 '.$this->start_time);
        $end = strtotime('1970-01-01 '.$this->end_time);

        if ($end <= $start) {
            $end += 86400;
        }

        return round(($end - $start) / 3600, 2);
    }
}
