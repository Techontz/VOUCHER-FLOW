<?php

namespace App\Models\Erp\Hr;

/**
 * A kind of leave and its yearly entitlement. A null entitlement means no
 * limit (unpaid leave); unpaid leave reduces pay in the payroll run.
 */
class LeaveType extends HrModel
{
    protected $table = 'hr_leave_types';

    protected function hrCasts(): array
    {
        return [
            'days_per_year' => 'decimal:2',
            'paid' => 'boolean',
            'accrues_monthly' => 'boolean',
            'is_active' => 'boolean',
        ];
    }

    public function isLimited(): bool
    {
        return $this->days_per_year !== null;
    }
}
