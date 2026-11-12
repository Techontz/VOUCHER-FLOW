<?php

namespace App\Models\Erp\Hr;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One person's pay for one run, with every figure it was computed from. */
class Payslip extends HrModel
{
    public const MONEY = [
        'basic', 'housing_allowance', 'transport_allowance', 'other_allowance', 'overtime', 'other_earnings',
        'absence_deduction', 'gross', 'nssf_employee', 'taxable', 'paye', 'heslb', 'loans', 'other_deductions',
        'total_deductions', 'net', 'nssf_employer', 'wcf', 'sdl',
    ];

    protected $table = 'hr_payslips';

    protected function hrCasts(): array
    {
        return [
            ...array_fill_keys(self::MONEY, 'decimal:2'),
            'payroll_run_id' => 'integer',
            'employee_id' => 'integer',
            'days_paid' => 'decimal:2',
            'unpaid_days' => 'decimal:2',
            'overtime_hours' => 'decimal:2',
            'lines' => 'array',
        ];
    }

    public function run(): BelongsTo
    {
        return $this->belongsTo(PayrollRun::class, 'payroll_run_id');
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }
}
