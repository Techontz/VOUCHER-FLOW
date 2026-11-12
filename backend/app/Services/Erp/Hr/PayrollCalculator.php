<?php

namespace App\Services\Erp\Hr;

use App\Models\Erp\Hr\Contract;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\HrSetting;
use App\Models\Erp\Hr\Loan;
use App\Models\Erp\Hr\PayItem;
use App\Models\Erp\Hr\StatutoryRate;
use Illuminate\Support\Carbon;
use RuntimeException;

/**
 * One person's pay for one month, from their contract, the month's attendance
 * and leave, their loans and pay items, and the statutory rates in force.
 *
 *   gross    = basic + allowances + overtime + other earnings - absence
 *   NSSF     = rate x gross (employee and employer shares)
 *   taxable  = gross - employee NSSF
 *   PAYE     = banded tax on taxable
 *   HESLB    = rate x basic, for loan beneficiaries
 *   net      = gross - NSSF - PAYE - HESLB - loan instalments - other deductions
 *   employer = NSSF employer share, WCF and SDL on gross (SDL unless exempt)
 *
 * Every figure is rounded to the cent as it is made, and the net is derived
 * from the rounded figures, so a payslip always adds up exactly.
 */
class PayrollCalculator
{
    /**
     * @param  array<string, StatutoryRate>  $rates
     * @param  array{absent?: int, overtime?: float}  $attendance
     * @return array<string, mixed>|null null when the person was not employed in the month
     */
    public function compute(
        Employee $employee,
        Contract $contract,
        Carbon $periodStart,
        Carbon $periodEnd,
        HrSetting $settings,
        array $rates,
        array $attendance = [],
        float $unpaidLeaveDays = 0,
    ): ?array {
        $period = $periodStart->format('Y-m');
        $from = $periodStart->copy()->max($employee->hire_date)->max($contract->start_date);
        $to = $periodEnd->copy();

        foreach ([$employee->exit_date, $contract->end_date] as $limit) {
            if ($limit && $limit->lt($to)) {
                $to = $limit->copy();
            }
        }

        if ($to->lt($from)) {
            return null;
        }

        $monthDays = $periodStart->daysInMonth;
        $daysPaid = (int) $from->diffInDays($to) + 1;
        $factor = $daysPaid >= $monthDays ? 1.0 : $daysPaid / $monthDays;
        $prorate = fn ($amount) => round((float) $amount * $factor, 2);

        $basic = $prorate($contract->basic_salary);
        $housing = $prorate($contract->housing_allowance);
        $transport = $prorate($contract->transport_allowance);
        $otherAllowance = $prorate($contract->other_allowance);

        $dailyRate = (float) $contract->basic_salary / max(1, (float) $settings->working_days_per_month);
        $hourlyRate = $dailyRate / max(1, (float) $settings->hours_per_day);

        $absent = $settings->deduct_absence ? (float) ($attendance['absent'] ?? 0) : 0.0;
        $unpaidDays = round($absent + $unpaidLeaveDays, 2);
        $absence = min($basic, round($dailyRate * $unpaidDays, 2));

        $overtimeHours = round((float) ($attendance['overtime'] ?? 0), 2);
        $overtime = round($overtimeHours * $hourlyRate * (float) $settings->overtime_multiplier, 2);

        $items = PayItem::query()->forPeriod($period)->where('employee_id', $employee->id)->orderBy('id')->get();
        $earningItems = $items->where('kind', 'earning');
        $deductionItems = $items->where('kind', 'deduction');
        $otherEarnings = round($earningItems->sum(fn ($i) => (float) $i->amount), 2);

        $gross = round($basic + $housing + $transport + $otherAllowance + $overtime + $otherEarnings - $absence, 2);

        $nssfEmployee = StatutoryRates::percent($rates['nssf_employee'], $gross);
        $taxable = round($gross - $nssfEmployee, 2);
        $paye = StatutoryRates::banded($rates['paye']->bands ?? [], $taxable);
        $heslb = $employee->heslb_beneficiary ? StatutoryRates::percent($rates['heslb'], $basic) : 0.0;

        $loanLines = Loan::query()
            ->where('employee_id', $employee->id)->where('status', Loan::STATUS_ACTIVE)
            ->where('start_period', '<=', $period)->where('balance', '>', 0)
            ->orderBy('id')->get()
            ->map(fn (Loan $loan) => [
                'loan_id' => $loan->id, 'number' => $loan->number, 'type' => $loan->type,
                'amount' => round(min((float) $loan->installment, (float) $loan->balance), 2),
            ])->values()->all();
        $loans = round(array_sum(array_column($loanLines, 'amount')), 2);
        $otherDeductions = round($deductionItems->sum(fn ($i) => (float) $i->amount), 2);

        $totalDeductions = round($nssfEmployee + $paye + $heslb + $loans + $otherDeductions, 2);
        $net = round($gross - $totalDeductions, 2);

        if ($net < 0) {
            throw new RuntimeException(sprintf(
                "%s's deductions (%s) are more than gross pay (%s) for %s. Reduce a loan instalment or a deduction, then prepare again.",
                $employee->full_name, number_format($totalDeductions, 2), number_format($gross, 2), $period,
            ));
        }

        $sdlApplies = ! $settings->sdl_exempt;

        return [
            'employee_id' => $employee->id,
            'employee_number' => $employee->employee_number,
            'employee_name' => $employee->full_name,
            'department' => $employee->department?->name,
            'job_title' => $employee->job_title,
            'bank_name' => $employee->bank_name,
            'bank_account_number' => $employee->bank_account_number,
            'days_paid' => $daysPaid,
            'unpaid_days' => $unpaidDays,
            'overtime_hours' => $overtimeHours,
            'basic' => $basic,
            'housing_allowance' => $housing,
            'transport_allowance' => $transport,
            'other_allowance' => $otherAllowance,
            'overtime' => $overtime,
            'other_earnings' => $otherEarnings,
            'absence_deduction' => $absence,
            'gross' => $gross,
            'nssf_employee' => $nssfEmployee,
            'taxable' => $taxable,
            'paye' => $paye,
            'heslb' => $heslb,
            'loans' => $loans,
            'other_deductions' => $otherDeductions,
            'total_deductions' => $totalDeductions,
            'net' => $net,
            'nssf_employer' => StatutoryRates::percent($rates['nssf_employer'], $gross),
            'wcf' => StatutoryRates::percent($rates['wcf'], $gross),
            'sdl' => $sdlApplies ? StatutoryRates::percent($rates['sdl'], $gross) : 0.0,
            'lines' => [
                'earnings' => $earningItems->map(fn ($i) => ['pay_item_id' => $i->id, 'category' => $i->category, 'description' => $i->description, 'amount' => (float) $i->amount])->values()->all(),
                'deductions' => $deductionItems->map(fn ($i) => ['pay_item_id' => $i->id, 'category' => $i->category, 'description' => $i->description, 'amount' => (float) $i->amount])->values()->all(),
                'loans' => $loanLines,
            ],
        ];
    }
}
