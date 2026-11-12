<?php

namespace App\Models\Erp\Hr;

/** A company's payroll and attendance policy: one row per company. */
class HrSetting extends HrModel
{
    protected $table = 'hr_settings';

    protected function hrCasts(): array
    {
        return [
            'sdl_exempt' => 'boolean',
            'deduct_absence' => 'boolean',
            'working_days_per_month' => 'decimal:2',
            'hours_per_day' => 'decimal:2',
            'overtime_multiplier' => 'decimal:2',
        ];
    }

    public static function current(): self
    {
        return self::query()->firstOrCreate([]);
    }
}
