<?php

namespace Tests\Feature;

use App\Models\Erp\Account;
use App\Models\Erp\Hr\Loan;
use App\Models\Erp\Hr\PayrollRun;
use App\Models\Erp\Hr\Payslip;
use App\Models\Erp\JournalEntry;
use App\Models\Erp\JournalLine;
use App\Services\Erp\Hr\StatutoryRates;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Payroll: statutory deductions from data, prepare -> authorise -> lock ->
 * post -> pay with separation of duties, and acceptance criterion 10: the sum
 * of the payslips is the run's totals is what the ledger received.
 */
class ErpHrPayrollTest extends TestCase
{
    use ErpHrSupport, RefreshDatabase, TestSupport;

    public function test_paye_follows_the_tanzanian_bands_at_their_edges(): void
    {
        $bands = StatutoryRates::DEFAULTS['TZ'][0]['bands'];

        $this->assertSame(0.0, StatutoryRates::banded($bands, 0));
        $this->assertSame(0.0, StatutoryRates::banded($bands, 270000));
        $this->assertSame(0.08, StatutoryRates::banded($bands, 270001));
        $this->assertSame(20000.0, StatutoryRates::banded($bands, 520000));
        $this->assertSame(20000.2, StatutoryRates::banded($bands, 520001));
        $this->assertSame(68000.0, StatutoryRates::banded($bands, 760000));
        $this->assertSame(68000.25, StatutoryRates::banded($bands, 760001));
        $this->assertSame(128000.0, StatutoryRates::banded($bands, 1000000));
        $this->assertSame(128000.3, StatutoryRates::banded($bands, 1000001));
        $this->assertSame(278000.0, StatutoryRates::banded($bands, 1500000));
    }

    public function test_a_payslip_applies_nssf_paye_wcf_sdl_and_heslb_from_the_rates_table(): void
    {
        $hr = $this->setUpHr();
        $this->hire($hr, ['full_name' => 'Juma Said', 'heslb_beneficiary' => true], [
            'type' => 'permanent', 'start_date' => '2025-01-01', 'basic_salary' => 1200000,
            'housing_allowance' => 200000, 'transport_allowance' => 100000,
        ])->assertCreated();

        $runId = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $this->lastMonth()])
            ->assertCreated()->assertJsonPath('data.status', 'draft')->json('data.id');

        $slip = Payslip::acrossTenants()->where('payroll_run_id', $runId)->firstOrFail();

        $this->assertEquals(1500000, (float) $slip->gross);
        $this->assertEquals(150000, (float) $slip->nssf_employee);       // 10% of gross
        $this->assertEquals(1350000, (float) $slip->taxable);
        $this->assertEquals(233000, (float) $slip->paye);                // 128,000 + 30% of 350,000
        $this->assertEquals(180000, (float) $slip->heslb);               // 15% of basic
        $this->assertEquals(1500000 - 150000 - 233000 - 180000, (float) $slip->net);
        $this->assertEquals(150000, (float) $slip->nssf_employer);
        $this->assertEquals(7500, (float) $slip->wcf);                   // 0.5%
        $this->assertEquals(52500, (float) $slip->sdl);                  // 3.5%
    }

    public function test_a_new_rate_version_applies_from_its_effective_date_only(): void
    {
        $hr = $this->setUpHr();
        $this->hire($hr)->assertCreated();
        $admin = $hr['admin'];

        $this->actingAs($admin, 'sanctum')->postJson('/api/erp/hr/statutory-rates', [
            'code' => 'sdl', 'name' => 'SDL', 'kind' => 'percent', 'base' => 'gross', 'party' => 'employer',
            'rate' => 4, 'effective_from' => now()->startOfMonth()->toDateString(),
        ])->assertCreated();

        $last = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $this->lastMonth()])->json('data');
        $this->assertEquals(28000, (float) $last['sdl'], 'Last month keeps 3.5%.');

        $current = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => now()->format('Y-m')])->json('data');
        $this->assertEquals(32000, (float) $current['sdl'], 'This month uses the new 4%.');
    }

    public function test_payroll_totals_agree_with_payslips_and_the_posted_journals(): void
    {
        $hr = $this->setUpHr();
        $period = $this->lastMonth();

        $a = $this->hire($hr, ['full_name' => 'Asha Mwakyusa', 'heslb_beneficiary' => true])->json('data.id');
        $b = $this->hire($hr, ['full_name' => 'Baraka Mollel'], ['type' => 'permanent', 'start_date' => '2025-01-01', 'basic_salary' => 1234567.89, 'housing_allowance' => 150000.33, 'transport_allowance' => 80000])->json('data.id');
        $this->hire($hr, ['full_name' => 'Rehema Kisanga'], ['type' => 'fixed_term', 'start_date' => '2025-01-01', 'basic_salary' => 420000, 'transport_allowance' => 50000]);

        $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/loans', [
            'employee_id' => $b, 'type' => 'loan', 'principal' => 600000, 'installment' => 100000, 'start_period' => $period, 'issued_on' => now()->subMonths(2)->toDateString(),
        ])->assertCreated();
        $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/pay-items', [
            'employee_id' => $a, 'kind' => 'earning', 'category' => 'arrears', 'description' => 'Arrears March', 'amount' => 45000, 'start_period' => $period, 'end_period' => $period,
        ])->assertCreated();
        $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/pay-items', [
            'employee_id' => $a, 'kind' => 'deduction', 'category' => 'union', 'description' => 'TUICO dues', 'amount' => 8000, 'start_period' => $period,
        ])->assertCreated();

        $id = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $period])->assertCreated()->json('data.id');
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/authorise")->assertOk();
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/lock")->assertOk();
        $this->actingAs($hr['accountant'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/post")->assertOk()->assertJsonPath('data.status', 'posted');

        $run = PayrollRun::acrossTenants()->findOrFail($id);
        $slips = Payslip::acrossTenants()->where('payroll_run_id', $id)->get();
        $this->assertCount(3, $slips);

        // Sum of payslips = run totals, column by column, to the cent.
        $cents = fn ($v) => (int) round((float) $v * 100);
        foreach (['gross', 'nssf_employee', 'paye', 'heslb', 'loans', 'other_deductions', 'total_deductions', 'net', 'nssf_employer', 'wcf', 'sdl'] as $column) {
            $this->assertSame($slips->sum(fn ($s) => $cents($s->{$column})), $cents($run->{$column}), "Run {$column} must equal the sum of its payslips.");
        }

        // Each payslip adds up on its own.
        foreach ($slips as $slip) {
            $this->assertSame($cents($slip->gross) - $cents($slip->total_deductions), $cents($slip->net));
        }

        // Run totals = journal amounts, by account.
        $entry = JournalEntry::acrossTenants()->with('lines.account')->findOrFail($run->journal_entry_id);
        $by = fn (string $key, string $side) => $entry->lines->filter(fn ($l) => $l->account->system_key === $key)->sum(fn ($l) => $cents($l->{$side}));

        $this->assertSame($cents($run->gross), $by('salaries', 'debit'));
        $this->assertSame($cents($run->nssf_employer), $by('nssf_employer_expense', 'debit'));
        $this->assertSame($cents($run->wcf), $by('wcf_expense', 'debit'));
        $this->assertSame($cents($run->sdl), $by('sdl_expense', 'debit'));
        $this->assertSame($cents($run->paye), $by('paye_payable', 'credit'));
        $this->assertSame($cents($run->nssf_employee) + $cents($run->nssf_employer), $by('nssf_payable', 'credit'));
        $this->assertSame($cents($run->heslb), $by('heslb_payable', 'credit'));
        $this->assertSame($cents($run->loans), $by('staff_loan_recoveries', 'credit'));
        $this->assertSame($cents($run->other_deductions), $by('payroll_deductions_payable', 'credit'));
        $this->assertSame($cents($run->net), $by('net_salaries_payable', 'credit'));
        $this->assertSame($entry->lines->sum(fn ($l) => $cents($l->debit)), $entry->lines->sum(fn ($l) => $cents($l->credit)), 'The journal balances.');

        // Posting is exactly once.
        $this->actingAs($hr['accountant'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/post")->assertStatus(422);
        $this->assertSame(1, JournalEntry::acrossTenants()->where('source_type', 'PayrollRun')->where('source_id', $id)->where('purpose', 'post')->count());

        // The loan was recovered once.
        $loan = Loan::acrossTenants()->where('employee_id', $b)->firstOrFail();
        $this->assertEquals(500000, (float) $loan->balance);
        $this->assertSame(1, $loan->repayments()->count());

        // Payment: Dr net salaries payable / Cr bank, once.
        $bank = Account::acrossTenants()->where('company_id', $hr['company']->id)->where('system_key', 'bank')->firstOrFail();
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/pay", ['account_id' => $bank->id])->assertOk()->assertJsonPath('data.status', 'paid');
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/pay", ['account_id' => $bank->id])->assertStatus(422);

        $payment = JournalEntry::acrossTenants()->findOrFail($run->fresh()->payment_journal_id);
        $this->assertSame($cents($run->net), JournalLine::query()->where('journal_entry_id', $payment->id)->where('account_id', $bank->id)->get()->sum(fn ($l) => $cents($l->credit)));
        $this->assertSame(1, JournalEntry::acrossTenants()->where('source_type', 'PayrollRun')->where('source_id', $id)->where('purpose', 'pay')->count());
    }

    public function test_salaries_cannot_be_paid_from_an_account_that_is_not_cash_or_bank(): void
    {
        $hr = $this->setUpHr();
        $this->hire($hr);
        $id = $this->preparePostedRun($hr);

        $sales = Account::acrossTenants()->where('company_id', $hr['company']->id)->where('system_key', 'sales')->firstOrFail();
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/pay", ['account_id' => $sales->id])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'cash or bank'));
    }

    public function test_the_preparer_cannot_authorise_their_own_run(): void
    {
        $hr = $this->setUpHr();
        $this->hire($hr);

        // The administrator holds every permission, and still cannot authorise what they prepared.
        $id = $this->actingAs($hr['admin'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $this->lastMonth()])->assertCreated()->json('data.id');
        $this->actingAs($hr['admin'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/authorise")
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'cannot authorise'));

        // The HR manager prepares but has no authority to authorise at all.
        $this->actingAs($hr['hr'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/authorise")->assertForbidden();

        $this->actingAs($hr['ceo'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/authorise")->assertOk()->assertJsonPath('data.status', 'authorised');
    }

    public function test_a_locked_run_cannot_change(): void
    {
        $hr = $this->setUpHr();
        $employee = $this->hire($hr)->json('data.id');
        $id = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $this->lastMonth()])->json('data.id');
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/authorise")->assertOk();
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/lock")->assertOk();
        $net = (float) PayrollRun::acrossTenants()->findOrFail($id)->net;

        // A raise after locking changes nothing on the locked run.
        $this->actingAs($hr['admin'], 'sanctum')->postJson("/api/erp/hr/employees/{$employee}/contracts", [
            'type' => 'permanent', 'start_date' => now()->startOfMonth()->subMonths(2)->toDateString(), 'basic_salary' => 2000000,
        ])->assertCreated();

        $this->actingAs($hr['hr'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/recalculate")->assertStatus(422);
        $this->actingAs($hr['hr'], 'sanctum')->deleteJson("/api/erp/hr/payroll-runs/{$id}")->assertStatus(422);
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/return", ['reason' => 'Try'])->assertStatus(422);
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/authorise")->assertStatus(422);

        $this->assertSame($net, (float) PayrollRun::acrossTenants()->findOrFail($id)->net);
        $this->actingAs($hr['accountant'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/post")->assertOk();
        $this->assertSame($net, (float) PayrollRun::acrossTenants()->findOrFail($id)->net);
    }

    public function test_a_draft_can_be_recalculated_and_a_month_has_one_run(): void
    {
        $hr = $this->setUpHr();
        $this->hire($hr);
        $id = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $this->lastMonth()])->json('data.id');

        $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $this->lastMonth()])->assertStatus(422);
        $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => now()->addMonth()->format('Y-m')])->assertStatus(422);
        $this->actingAs($hr['hr'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/recalculate")->assertOk();
    }

    public function test_absence_reduces_gross_and_a_joiner_is_paid_pro_rata(): void
    {
        $hr = $this->setUpHr();
        $start = now()->startOfMonth()->subMonth();
        $asha = $this->hire($hr)->json('data.id');
        $this->hire($hr, ['full_name' => 'New Joiner', 'hire_date' => $start->copy()->addDays(15)->toDateString()], [
            'type' => 'permanent', 'start_date' => $start->copy()->addDays(15)->toDateString(), 'basic_salary' => 900000,
        ]);

        $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/attendance', [
            'employee_id' => $asha, 'date' => $start->copy()->addDays(2)->toDateString(), 'status' => 'absent',
        ])->assertCreated();

        $id = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $start->format('Y-m')])->json('data.id');
        $slips = Payslip::acrossTenants()->where('payroll_run_id', $id)->get()->keyBy('employee_name');

        $this->assertEquals(round(800000 / 26, 2), (float) $slips['Asha Mwakyusa']->absence_deduction);
        $this->assertEquals(round(800000 - 800000 / 26, 2), (float) $slips['Asha Mwakyusa']->gross);

        $days = $start->daysInMonth - 15;
        $this->assertEquals(round(900000 * $days / $start->daysInMonth, 2), (float) $slips['New Joiner']->basic);
    }

    public function test_payroll_needs_payroll_permissions_and_stays_inside_the_company(): void
    {
        $hr = $this->setUpHr();
        $this->hire($hr);
        $id = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $this->lastMonth()])->json('data.id');
        $slip = Payslip::acrossTenants()->where('payroll_run_id', $id)->value('id');

        $this->actingAs($hr['employee'], 'sanctum')->getJson('/api/erp/hr/payroll-runs')->assertForbidden();
        $this->actingAs($hr['employee'], 'sanctum')->getJson("/api/erp/hr/payslips/{$slip}")->assertForbidden();
        $this->actingAs($hr['accountant'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => now()->format('Y-m')])->assertForbidden();
        $this->actingAs($hr['ceo'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/post")->assertForbidden();

        $other = $this->setUpHr('Bahari Foods');
        $this->actingAs($other['hr'], 'sanctum')->getJson("/api/erp/hr/payroll-runs/{$id}")->assertNotFound();
        $this->actingAs($other['hr'], 'sanctum')->getJson("/api/erp/hr/payslips/{$slip}")->assertNotFound();
        $this->actingAs($other['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/authorise")->assertNotFound();
    }

    public function test_payslip_pdf_downloads(): void
    {
        $hr = $this->setUpHr();
        $this->hire($hr);
        $id = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $this->lastMonth()])->json('data.id');
        $slip = Payslip::acrossTenants()->where('payroll_run_id', $id)->value('id');

        $this->actingAs($hr['hr'], 'sanctum')->get("/api/erp/hr/payslips/{$slip}/pdf")->assertOk()->assertHeader('content-type', 'application/pdf');
    }

    private function preparePostedRun(array $hr): int
    {
        $id = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $this->lastMonth()])->json('data.id');
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/authorise")->assertOk();
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/lock")->assertOk();
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/post")->assertOk();

        return $id;
    }
}
