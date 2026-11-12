<?php

namespace App\Services\Erp\Hr;

use App\Models\Erp\Account;
use App\Models\Erp\Hr\Contract;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\HrSetting;
use App\Models\Erp\Hr\Loan;
use App\Models\Erp\Hr\LoanRepayment;
use App\Models\Erp\Hr\PayrollRun;
use App\Models\Erp\Hr\Payslip;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * A month's payroll from preparation to payment.
 *
 *   draft       prepared and recalculable; its payslips are the preview
 *   authorised  approved by someone other than the preparer
 *   locked      frozen: nothing about it can change again
 *   posted      on the ledger, once: Dr salaries and employer costs,
 *               Cr each statutory payable, loan recoveries and net pay
 *   paid        net pay settled from a bank or cash account, once
 *
 * Each step locks the run row and re-checks its status, so two people
 * pressing the same button cannot move it twice; the journals are keyed to
 * the run so the ledger refuses a second posting as well.
 */
class PayrollService
{
    public function __construct(
        private readonly PayrollCalculator $calculator,
        private readonly StatutoryRates $rates,
        private readonly AttendanceService $attendance,
        private readonly LeaveService $leave,
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    /** @return array{run: PayrollRun, skipped: list<string>} */
    public function prepare(string $period, User $actor, ?string $notes = null): array
    {
        $start = $this->periodStart($period);

        if ($start->gt(now()->startOfMonth())) {
            throw new RuntimeException('Payroll cannot be prepared for a month that has not started.');
        }

        return DB::transaction(function () use ($period, $start, $actor, $notes) {
            if ($existing = PayrollRun::query()->where('period', $period)->first()) {
                throw new RuntimeException("A payroll run for {$start->format('F Y')} already exists ({$existing->number}).");
            }

            $run = PayrollRun::create([
                'number' => $this->numbers->next('PAY'),
                'period' => $period,
                'period_start' => $start->toDateString(),
                'period_end' => $start->copy()->endOfMonth()->toDateString(),
                'status' => PayrollRun::STATUS_DRAFT,
                'notes' => $notes,
                'prepared_by' => $actor->id,
                'prepared_at' => now(),
            ]);

            $skipped = $this->calculate($run);
            $this->audit->log('hr.payroll.prepared', "Prepared payroll {$run->number} for {$start->format('F Y')}: {$run->employees_count} payslips, net ".number_format((float) $run->net, 2), $run, actor: $actor);

            return ['run' => $run->fresh(), 'skipped' => $skipped];
        });
    }

    /** @return array{run: PayrollRun, skipped: list<string>} */
    public function recalculate(PayrollRun $run, User $actor): array
    {
        return DB::transaction(function () use ($run, $actor) {
            $locked = $this->lock($run);
            $this->assertStatus($locked, PayrollRun::STATUS_DRAFT, 'recalculated');

            $skipped = $this->calculate($locked);
            $locked->update(['prepared_by' => $actor->id, 'prepared_at' => now()]);
            $this->audit->log('hr.payroll.recalculated', "Recalculated payroll {$locked->number}", $locked, actor: $actor);

            return ['run' => $locked->fresh(), 'skipped' => $skipped];
        });
    }

    public function authorise(PayrollRun $run, User $actor): PayrollRun
    {
        return DB::transaction(function () use ($run, $actor) {
            $locked = $this->lock($run);
            $this->assertStatus($locked, PayrollRun::STATUS_DRAFT, 'authorised');

            if ($locked->prepared_by === $actor->id) {
                throw new RuntimeException('The person who prepared a payroll run cannot authorise it. Ask another authoriser.');
            }

            $locked->update(['status' => PayrollRun::STATUS_AUTHORISED, 'authorised_by' => $actor->id, 'authorised_at' => now()]);
            $this->audit->log('hr.payroll.authorised', "Authorised payroll {$locked->number}", $locked, actor: $actor);

            return $locked->fresh();
        });
    }

    /** Sends an authorised run back to draft so it can be corrected. */
    public function returnToDraft(PayrollRun $run, User $actor, string $reason): PayrollRun
    {
        return DB::transaction(function () use ($run, $actor, $reason) {
            $locked = $this->lock($run);
            $this->assertStatus($locked, PayrollRun::STATUS_AUTHORISED, 'returned');

            $locked->update(['status' => PayrollRun::STATUS_DRAFT, 'authorised_by' => null, 'authorised_at' => null]);
            $this->audit->log('hr.payroll.returned', "Returned payroll {$locked->number} to draft: {$reason}", $locked, actor: $actor);

            return $locked->fresh();
        });
    }

    public function lockRun(PayrollRun $run, User $actor): PayrollRun
    {
        return DB::transaction(function () use ($run, $actor) {
            $locked = $this->lock($run);
            $this->assertStatus($locked, PayrollRun::STATUS_AUTHORISED, 'locked');

            $locked->update(['status' => PayrollRun::STATUS_LOCKED, 'locked_by' => $actor->id, 'locked_at' => now()]);
            $this->audit->log('hr.payroll.locked', "Locked payroll {$locked->number}", $locked, actor: $actor);

            return $locked->fresh();
        });
    }

    public function post(PayrollRun $run, User $actor): PayrollRun
    {
        return DB::transaction(function () use ($run, $actor) {
            $locked = $this->lock($run);
            $this->assertStatus($locked, PayrollRun::STATUS_LOCKED, 'posted');

            $this->recoverLoans($locked);

            $entry = null;
            if (BusinessConfig::of($this->tenant->company())->postsToLedger()) {
                $entry = $this->journal->post(
                    $this->postingLines($locked),
                    "Payroll {$locked->number} for {$locked->period_start->format('F Y')}",
                    $locked->period_end->toDateString(),
                    $locked, 'post', $actor,
                );
            }

            $locked->update([
                'status' => PayrollRun::STATUS_POSTED, 'posted_by' => $actor->id, 'posted_at' => now(),
                'journal_entry_id' => $entry?->id,
            ]);
            $this->audit->log('hr.payroll.posted', "Posted payroll {$locked->number}".($entry ? " as {$entry->number}" : ''), $locked, actor: $actor);

            return $locked->fresh();
        });
    }

    public function pay(PayrollRun $run, int $accountId, ?string $date, User $actor): PayrollRun
    {
        return DB::transaction(function () use ($run, $accountId, $date, $actor) {
            $locked = $this->lock($run);
            $this->assertStatus($locked, PayrollRun::STATUS_POSTED, 'paid');

            $account = Account::query()->whereKey($accountId)->where('type', 'asset')->where('is_active', true)
                ->whereBetween('code', ['1100', '1299'])->first()
                ?? throw new RuntimeException('Pay salaries from an active cash or bank account (codes 1100 to 1299).');

            $date ??= now()->toDateString();
            $entry = null;

            if ($locked->journal_entry_id && (float) $locked->net > 0) {
                $entry = $this->journal->post([
                    ['account' => 'net_salaries_payable', 'debit' => $locked->net, 'description' => $locked->number],
                    ['account_id' => $account->id, 'credit' => $locked->net, 'description' => $locked->number],
                ], "Salaries paid, payroll {$locked->number}", $date, $locked, 'pay', $actor);
            }

            $locked->update([
                'status' => PayrollRun::STATUS_PAID, 'paid_by' => $actor->id, 'paid_at' => now(), 'payment_date' => $date,
                'payment_account_id' => $account->id, 'payment_journal_id' => $entry?->id,
            ]);
            $this->audit->log('hr.payroll.paid', "Paid net salaries of payroll {$locked->number} from {$account->code} {$account->name}", $locked, actor: $actor);

            return $locked->fresh();
        });
    }

    public function delete(PayrollRun $run, User $actor): void
    {
        DB::transaction(function () use ($run, $actor) {
            $locked = $this->lock($run);
            $this->assertStatus($locked, PayrollRun::STATUS_DRAFT, 'deleted');

            $locked->payslips()->delete();
            $locked->delete();
            $this->audit->log('hr.payroll.deleted', "Deleted draft payroll {$locked->number}", $locked, actor: $actor);
        });
    }

    /**
     * The journal a locked run posts. Debits: gross pay and the employer's
     * statutory costs. Credits: every amount now owed to someone.
     *
     * @return list<array<string, mixed>>
     */
    public function postingLines(PayrollRun $run): array
    {
        $memo = $run->number;
        $lines = [
            ['account' => 'salaries', 'debit' => $run->gross],
            ['account' => 'nssf_employer_expense', 'debit' => $run->nssf_employer],
            ['account' => 'wcf_expense', 'debit' => $run->wcf],
            ['account' => 'sdl_expense', 'debit' => $run->sdl],
            ['account' => 'paye_payable', 'credit' => $run->paye],
            ['account' => 'nssf_payable', 'credit' => round((float) $run->nssf_employee + (float) $run->nssf_employer, 2)],
            ['account' => 'wcf_payable', 'credit' => $run->wcf],
            ['account' => 'sdl_payable', 'credit' => $run->sdl],
            ['account' => 'heslb_payable', 'credit' => $run->heslb],
            ['account' => 'staff_loan_recoveries', 'credit' => $run->loans],
            ['account' => 'payroll_deductions_payable', 'credit' => $run->other_deductions],
            ['account' => 'net_salaries_payable', 'credit' => $run->net],
        ];

        return array_values(array_map(
            fn ($l) => [...$l, 'description' => $memo],
            array_filter($lines, fn ($l) => round((float) ($l['debit'] ?? $l['credit']), 2) > 0),
        ));
    }

    public function periodStart(string $period): Carbon
    {
        if (! preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $period)) {
            throw new RuntimeException('A pay period is a month written as YYYY-MM.');
        }

        return Carbon::parse("{$period}-01")->startOfDay();
    }

    /**
     * Rebuilds a draft run's payslips and totals from today's data.
     *
     * @return list<string> people left out, and why
     */
    private function calculate(PayrollRun $run): array
    {
        $start = $run->period_start->copy();
        $end = $run->period_end->copy();
        $settings = HrSetting::current();
        $rates = $this->rates->inForce($end, $settings->country);
        $attendance = $this->attendance->summary($start, $end);
        $unpaid = $this->leave->unpaidDays($start, $end);
        $skipped = [];

        $run->payslips()->delete();

        $employees = Employee::query()->with('department')
            ->whereDate('hire_date', '<=', $end)
            ->where(fn ($q) => $q->where('status', '!=', Employee::STATUS_EXITED)->orWhereDate('exit_date', '>=', $start))
            ->orderBy('employee_number')->get();

        foreach ($employees as $employee) {
            $contract = Contract::query()
                ->where('employee_id', $employee->id)
                ->whereDate('start_date', '<=', $end)
                ->where(fn ($q) => $q->whereNull('end_date')->orWhereDate('end_date', '>=', $start))
                ->orderByDesc('start_date')->orderByDesc('id')
                ->first();

            if (! $contract) {
                $skipped[] = "{$employee->full_name} ({$employee->employee_number}): no contract covers this month.";

                continue;
            }

            $slip = $this->calculator->compute(
                $employee, $contract, $start, $end, $settings, $rates,
                $attendance[$employee->id] ?? [], (float) ($unpaid[$employee->id] ?? 0),
            );

            if ($slip) {
                $run->payslips()->create($slip);
            }
        }

        $payslips = $run->payslips()->get();

        if ($payslips->isEmpty()) {
            throw new RuntimeException('No one has a contract covering this month, so there is nothing to pay.');
        }

        $run->update([...$this->totals($payslips), 'rates' => array_map(StatutoryRates::describe(...), $rates)]);

        return $skipped;
    }

    /**
     * Run totals as the exact sum of the payslips, added in whole cents.
     *
     * @param  iterable<Payslip>  $payslips
     * @return array<string, mixed>
     */
    private function totals(iterable $payslips): array
    {
        $cents = array_fill_keys(PayrollRun::TOTALS, 0);
        $count = 0;

        foreach ($payslips as $slip) {
            $count++;
            foreach (PayrollRun::TOTALS as $column) {
                $value = $column === 'allowances'
                    ? (float) $slip->housing_allowance + (float) $slip->transport_allowance + (float) $slip->other_allowance
                    : (float) $slip->{$column};
                $cents[$column] += (int) round($value * 100);
            }
        }

        return ['employees_count' => $count, ...array_map(fn ($c) => $c / 100, $cents)];
    }

    /** Records each loan instalment the run deducted and lowers the loan's balance. */
    private function recoverLoans(PayrollRun $run): void
    {
        foreach ($run->payslips()->get() as $slip) {
            foreach ($slip->lines['loans'] ?? [] as $line) {
                $loan = Loan::query()->whereKey($line['loan_id'])->lockForUpdate()->first();

                if (! $loan || (float) $line['amount'] <= 0) {
                    continue;
                }

                $balance = max(0, round((float) $loan->balance - (float) $line['amount'], 2));
                LoanRepayment::create([
                    'loan_id' => $loan->id, 'payroll_run_id' => $run->id, 'period' => $run->period,
                    'amount' => $line['amount'], 'balance_after' => $balance,
                ]);
                $loan->update(['balance' => $balance, 'status' => $balance <= 0 ? Loan::STATUS_SETTLED : $loan->status]);
            }
        }
    }

    private function lock(PayrollRun $run): PayrollRun
    {
        return PayrollRun::query()->whereKey($run->id)->lockForUpdate()->firstOrFail();
    }

    private function assertStatus(PayrollRun $run, string $expected, string $verb): void
    {
        if ($run->status !== $expected) {
            throw new RuntimeException("Payroll {$run->number} is {$run->status} and cannot be {$verb}.");
        }
    }
}
