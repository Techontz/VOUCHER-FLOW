<?php

namespace Tests\Feature;

use App\Models\Erp\Account;
use App\Models\Erp\JournalEntry;
use App\Models\User;
use App\Services\Erp\Finance\PeriodLock;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use RuntimeException;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Finance: bank accounts, transfers, the cashbook, reconciliation, the
 * statements, period closing and budgets. Every posting is checked against
 * the trial balance, the source of truth.
 */
class ErpFinanceTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    /** @return array<string, mixed> */
    private function finance(string $name = 'Maji Bora'): array
    {
        return $this->setUpErp($this->makeTenant($name));
    }

    private function bank(array $erp, string $name, float $opening = 0, string $type = 'bank', ?string $date = null): array
    {
        return $this->actingAs($erp['finance'], 'sanctum')->postJson('/api/erp/finance/bank-accounts', [
            'name' => $name, 'type' => $type, 'bank_name' => $name, 'account_number' => (string) random_int(10000, 99999),
            'opening_balance' => $opening, 'opening_date' => $date ?? now()->subMonths(3)->startOfMonth()->toDateString(),
        ])->assertCreated()->json('data');
    }

    private function account(array $erp, string $key): Account
    {
        return app(TenantContext::class)->forCompany($erp['company'], fn () => Account::where('system_key', $key)->firstOrFail());
    }

    private function cashbook(array $erp, array $bank, string $type, float $amount, string $key, ?string $date = null, bool $post = true): array
    {
        $entry = $this->actingAs($erp['finance'], 'sanctum')->postJson('/api/erp/finance/cashbook', [
            'type' => $type, 'entry_date' => $date ?? now()->toDateString(), 'bank_account_id' => $bank['id'],
            'account_id' => $this->account($erp, $key)->id, 'amount' => $amount, 'description' => ucfirst($key),
        ])->assertCreated()->json('data');

        return $post ? $this->postJson("/api/erp/finance/cashbook/{$entry['id']}/post")->assertOk()->json('data') : $entry;
    }

    private function trialBalance(array $erp, ?string $to = null, ?string $from = null): array
    {
        return $this->actingAs($erp['finance'], 'sanctum')->getJson('/api/erp/trial-balance?'.http_build_query(array_filter(['from' => $from, 'to' => $to])))->json('data');
    }

    private function tbBalance(array $tb, string $code): float
    {
        return (float) (collect($tb['rows'])->firstWhere('code', $code)['balance'] ?? 0);
    }

    public function test_a_bank_account_gets_its_own_ledger_account_and_its_opening_balance_posts_once(): void
    {
        $erp = $this->finance();
        $nmb = $this->bank($erp, 'NMB Bank', 5_000_000);
        $crdb = $this->bank($erp, 'CRDB Bank', 0);

        $this->assertSame('1210', $nmb['account']['code']);
        $this->assertSame('1220', $crdb['account']['code']);

        $tb = $this->trialBalance($erp);
        $this->assertTrue($tb['balanced']);
        $this->assertEquals(5_000_000, $this->tbBalance($tb, '1210'));
        $this->assertEquals(5_000_000, $this->tbBalance($tb, '3900'));

        // The opening entry is keyed to the bank account: once only.
        $count = app(TenantContext::class)->forCompany($erp['company'], fn () => JournalEntry::where('source_type', 'BankAccount')->count());
        $this->assertSame(1, $count);

        $this->getJson('/api/erp/finance/bank-accounts')->assertOk()->assertJsonPath('data.1.balance', 5_000_000);
    }

    public function test_a_transfer_posts_once_with_charges_and_reverses_cleanly(): void
    {
        $erp = $this->finance();
        $nmb = $this->bank($erp, 'NMB Bank', 10_000_000);
        $mpesa = $this->bank($erp, 'M-Pesa till', 0, 'mobile_money');

        $id = $this->postJson('/api/erp/finance/transfers', [
            'transfer_date' => now()->toDateString(), 'from_bank_account_id' => $nmb['id'], 'to_bank_account_id' => $mpesa['id'],
            'amount' => 2_000_000, 'charges' => 5_000, 'reference' => 'TT-1',
        ])->assertCreated()->assertJsonPath('data.status', 'draft')->json('data.id');

        // A draft changes nothing.
        $this->assertEquals(10_000_000, $this->tbBalance($this->trialBalance($erp), '1210'));

        $this->postJson("/api/erp/finance/transfers/{$id}/post")->assertOk()->assertJsonPath('data.status', 'posted');
        $this->postJson("/api/erp/finance/transfers/{$id}/post")->assertStatus(422);

        $tb = $this->trialBalance($erp);
        $this->assertTrue($tb['balanced']);
        $this->assertEquals(7_995_000, $this->tbBalance($tb, '1210'));
        $this->assertEquals(2_000_000, $this->tbBalance($tb, '1220'));
        $this->assertEquals(5_000, $this->tbBalance($tb, '6610'));

        $this->postJson("/api/erp/finance/transfers/{$id}/reverse", ['reason' => 'Wrong till'])->assertOk()->assertJsonPath('data.status', 'reversed');
        $this->postJson("/api/erp/finance/transfers/{$id}/reverse", ['reason' => 'Again'])->assertStatus(422);

        $tb = $this->trialBalance($erp);
        $this->assertTrue($tb['balanced']);
        $this->assertEquals(10_000_000, $this->tbBalance($tb, '1210'));
        $this->assertEquals(0, $this->tbBalance($tb, '1220'));
        $this->assertEquals(0, $this->tbBalance($tb, '6610'));

        // Mobile money cannot go below zero; a transfer between one account and itself is refused.
        $out = $this->postJson('/api/erp/finance/transfers', [
            'transfer_date' => now()->toDateString(), 'from_bank_account_id' => $mpesa['id'], 'to_bank_account_id' => $nmb['id'], 'amount' => 1,
        ])->json('data.id');
        $this->postJson("/api/erp/finance/transfers/{$out}/post")->assertStatus(422);
        $this->postJson('/api/erp/finance/transfers', [
            'transfer_date' => now()->toDateString(), 'from_bank_account_id' => $nmb['id'], 'to_bank_account_id' => $nmb['id'], 'amount' => 1,
        ])->assertStatus(422)->assertJsonValidationErrors('to_bank_account_id');
    }

    public function test_cashbook_receipts_and_payments_post_once_and_reverse_cleanly(): void
    {
        $erp = $this->finance();
        $nmb = $this->bank($erp, 'NMB Bank', 1_000_000);

        $receipt = $this->cashbook($erp, $nmb, 'receipt', 400_000, 'other_income');
        $this->assertStringStartsWith('CBR-', $receipt['number']);
        $payment = $this->cashbook($erp, $nmb, 'payment', 250_000, 'rent');
        $this->assertStringStartsWith('CBP-', $payment['number']);

        $this->postJson("/api/erp/finance/cashbook/{$payment['id']}/post")->assertStatus(422);

        $tb = $this->trialBalance($erp);
        $this->assertTrue($tb['balanced']);
        $this->assertEquals(1_150_000, $this->tbBalance($tb, '1210'));
        $this->assertEquals(400_000, $this->tbBalance($tb, '4900'));
        $this->assertEquals(250_000, $this->tbBalance($tb, '6300'));

        $this->postJson("/api/erp/finance/cashbook/{$payment['id']}/reverse", ['reason' => 'Paid twice'])->assertOk();
        $tb = $this->trialBalance($erp);
        $this->assertEquals(1_400_000, $this->tbBalance($tb, '1210'));
        $this->assertEquals(0, $this->tbBalance($tb, '6300'));

        // A posted entry cannot be edited; a cash account is not a valid counter-account.
        $this->putJson("/api/erp/finance/cashbook/{$receipt['id']}", [
            'entry_date' => now()->toDateString(), 'bank_account_id' => $nmb['id'], 'account_id' => $this->account($erp, 'rent')->id,
            'amount' => 1, 'description' => 'x',
        ])->assertStatus(422);
        $this->postJson('/api/erp/finance/cashbook', [
            'type' => 'payment', 'entry_date' => now()->toDateString(), 'bank_account_id' => $nmb['id'],
            'account_id' => $this->account($erp, 'cash')->id, 'amount' => 10, 'description' => 'Float',
        ])->assertStatus(422);

        $this->getJson('/api/erp/finance/cashbook?status=posted')->assertOk()->assertJsonPath('totals.receipts', 400_000);
    }

    public function test_reconciliation_matches_statement_lines_and_completes_only_when_it_agrees(): void
    {
        $erp = $this->finance();
        $nmb = $this->bank($erp, 'NMB Bank', 1_000_000, 'bank', now()->subMonth()->startOfMonth()->toDateString());
        $day = now()->subMonth()->startOfMonth();

        $this->cashbook($erp, $nmb, 'receipt', 300_000, 'other_income', $day->copy()->addDays(2)->toDateString());
        $this->cashbook($erp, $nmb, 'payment', 120_000, 'utilities', $day->copy()->addDays(5)->toDateString());
        // Paid by cheque on the last day: not on the bank's statement yet.
        $this->cashbook($erp, $nmb, 'payment', 80_000, 'rent', $day->copy()->endOfMonth()->toDateString());

        // Statement: opening 1,000,000 + 300,000 - 120,000 - 2,500 charges = 1,177,500.
        $rec = $this->postJson('/api/erp/finance/reconciliations', [
            'bank_account_id' => $nmb['id'], 'statement_date' => $day->copy()->endOfMonth()->toDateString(),
            'statement_closing_balance' => 1_177_500,
        ])->assertCreated()->json('data');
        $this->assertEquals(1_000_000, $rec['statement_opening_balance']);

        // A second open reconciliation on the same account is refused.
        $this->postJson('/api/erp/finance/reconciliations', [
            'bank_account_id' => $nmb['id'], 'statement_date' => $day->copy()->endOfMonth()->toDateString(), 'statement_closing_balance' => 1,
        ])->assertStatus(422);

        $csv = "Date,Description,Amount,Reference\n"
            .$day->copy()->addDays(3)->format('d/m/Y').",Deposit,\"300,000.00\",D1\n"
            .$day->copy()->addDays(6)->toDateString().",TANESCO,-120000,P1\n"
            .$day->copy()->endOfMonth()->toDateString().",Ledger fees,-2500,\n";
        $this->postJson("/api/erp/finance/reconciliations/{$rec['id']}/import", ['csv' => $csv])
            ->assertCreated()->assertJsonPath('imported', 3)->assertJsonPath('matched', 2);

        $show = $this->getJson("/api/erp/finance/reconciliations/{$rec['id']}")->assertOk()->json('data');
        $summary = $show['summary'];
        $this->assertEquals(1_100_000, $summary['book_balance']);
        $this->assertEquals(80_000, $summary['outstanding_payments']);
        $this->assertEquals(0, $summary['deposits_in_transit']);
        $this->assertEquals(-2_500, $summary['unmatched_statement_total']);
        $this->assertEquals(1_097_500, $summary['adjusted_bank_balance']);
        $this->assertEquals(1_097_500, $summary['adjusted_book_balance']);
        $this->assertEquals(0, $summary['difference']);
        $this->assertEquals(0, $summary['statement_lines_difference']);

        // An unmatched line blocks completion; booking it fixes it.
        $this->postJson("/api/erp/finance/reconciliations/{$rec['id']}/complete")->assertStatus(422);
        $fees = collect($show['lines'])->firstWhere('description', 'Ledger fees');
        $this->postJson("/api/erp/finance/reconciliations/{$rec['id']}/lines/{$fees['id']}/create-entry", [
            'account_id' => $this->account($erp, 'bank_charges')->id,
        ])->assertOk();

        // A wrong amount cannot be matched; a journal line cannot be matched twice.
        $deposit = collect($show['lines'])->firstWhere('description', 'Deposit');
        $this->postJson("/api/erp/finance/reconciliations/{$rec['id']}/lines/{$deposit['id']}/unmatch")->assertOk();
        $rent = collect($this->getJson("/api/erp/finance/reconciliations/{$rec['id']}")->json('data.outstanding'))->firstWhere('amount', -80000);
        $this->postJson("/api/erp/finance/reconciliations/{$rec['id']}/lines/{$deposit['id']}/match", ['journal_line_id' => $rent['id']])->assertStatus(422);
        $this->postJson("/api/erp/finance/reconciliations/{$rec['id']}/auto-match")->assertOk()->assertJsonPath('matched', 1);

        $summary = $this->getJson("/api/erp/finance/reconciliations/{$rec['id']}")->json('data.summary');
        $this->assertEquals(1_097_500, $summary['book_balance']);
        $this->assertEquals(1_177_500, $summary['cleared_balance']);
        $this->assertEquals(0, $summary['difference']);

        $this->postJson("/api/erp/finance/reconciliations/{$rec['id']}/complete")->assertOk()->assertJsonPath('data.status', 'completed');
        $this->postJson("/api/erp/finance/reconciliations/{$rec['id']}/lines", ['lines' => [['line_date' => now()->toDateString(), 'description' => 'Late', 'amount' => 5]]])->assertStatus(422);
    }

    public function test_statements_agree_with_the_trial_balance_and_the_balance_sheet_balances(): void
    {
        $erp = $this->finance();
        $nmb = $this->bank($erp, 'NMB Bank', 20_000_000, 'bank', now()->subMonths(2)->startOfMonth()->toDateString());
        $crdb = $this->bank($erp, 'CRDB Bank', 3_000_000, 'bank', now()->subMonths(2)->startOfMonth()->toDateString());
        $lastMonth = now()->subMonth()->startOfMonth();

        $this->cashbook($erp, $nmb, 'receipt', 5_000_000, 'other_income', $lastMonth->copy()->addDays(3)->toDateString());
        $this->cashbook($erp, $nmb, 'payment', 1_200_000, 'rent', $lastMonth->copy()->addDays(4)->toDateString());
        $this->cashbook($erp, $crdb, 'payment', 450_000, 'utilities', $lastMonth->copy()->addDays(9)->toDateString());
        $this->cashbook($erp, $nmb, 'receipt', 2_000_000, 'owner_capital', $lastMonth->copy()->addDays(10)->toDateString());
        $this->cashbook($erp, $nmb, 'payment', 300_000, 'utilities', now()->startOfMonth()->toDateString());
        $transfer = $this->postJson('/api/erp/finance/transfers', [
            'transfer_date' => $lastMonth->copy()->addDays(12)->toDateString(), 'from_bank_account_id' => $nmb['id'],
            'to_bank_account_id' => $crdb['id'], 'amount' => 1_000_000, 'charges' => 10_000,
        ])->json('data.id');
        $this->postJson("/api/erp/finance/transfers/{$transfer}/post")->assertOk();

        // A manual journal with no cash: an accrual.
        $this->postJson('/api/erp/journals', ['memo' => 'Accrued audit fee', 'entry_date' => $lastMonth->copy()->endOfMonth()->toDateString(), 'lines' => [
            ['account_id' => $this->account($erp, 'admin')->id, 'debit' => 600_000],
            ['account_id' => $this->account($erp, 'accruals')->id, 'credit' => 600_000],
        ]])->assertCreated();

        $from = $lastMonth->toDateString();
        $to = $lastMonth->copy()->endOfMonth()->toDateString();

        $pl = $this->getJson("/api/erp/finance/statements/profit-and-loss?from={$from}&to={$to}")->assertOk()->json('data');
        $tb = $this->trialBalance($erp, $to, $from);
        $tbIncome = collect($tb['rows'])->where('type', 'income')->sum('balance');
        $tbExpense = collect($tb['rows'])->where('type', 'expense')->sum('balance');
        $this->assertEquals(round($tbIncome - $tbExpense, 2), $pl['totals']['net_profit']);
        $this->assertEquals(5_000_000 - 1_200_000 - 450_000 - 10_000 - 600_000, $pl['totals']['net_profit']);
        $this->assertSame(now()->subMonths(2)->startOfMonth()->toDateString(), $pl['prior_from']);
        $this->assertEquals(0, $pl['prior_totals']['net_profit']);

        foreach ([$to, now()->toDateString()] as $asOf) {
            $bs = $this->getJson("/api/erp/finance/statements/balance-sheet?as_of={$asOf}")->assertOk()->json('data');
            $this->assertTrue($bs['balanced']);
            $tbAll = $this->trialBalance($erp, $asOf);
            foreach ($bs['rows'] as $row) {
                $this->assertEquals($this->tbBalance($tbAll, $row['code']), $row['amount'], "Balance sheet {$row['code']} agrees with the trial balance");
            }
            $earnings = collect($tbAll['rows'])->where('type', 'income')->sum('balance') - collect($tbAll['rows'])->where('type', 'expense')->sum('balance');
            $this->assertEquals(round($earnings, 2), $bs['current_earnings']);
        }

        $cf = $this->getJson("/api/erp/finance/statements/cash-flow?from={$from}&to={$to}")->assertOk()->json('data');
        $this->assertTrue($cf['reconciles']);
        $this->assertEquals(23_000_000, $cf['totals']['opening_cash']);
        $cash = fn (array $tb) => collect($tb['rows'])->filter(fn ($r) => $r['type'] === 'asset' && (int) $r['code'] >= 1100 && (int) $r['code'] <= 1299)->sum('balance');
        $this->assertEquals(round($cash($this->trialBalance($erp, $to)), 2), $cf['totals']['closing_cash']);
        $this->assertEquals(2_000_000, $cf['totals']['financing']);
        $this->assertEquals(5_000_000 - 1_200_000 - 450_000 - 10_000, $cf['totals']['operating']);

        $csv = $this->get("/api/erp/finance/statements/profit-and-loss?from={$from}&to={$to}&format=csv")->assertOk();
        $this->assertStringContainsString('Net profit', $csv->streamedContent());
        $this->assertStringContainsString('text/csv', $csv->headers->get('Content-Type'));
    }

    public function test_a_closed_period_refuses_postings_and_the_year_end_closes_profit_to_retained_earnings_once(): void
    {
        $erp = $this->finance();
        $lastYear = now()->year - 1;
        $nmb = $this->bank($erp, 'NMB Bank', 1_000_000, 'bank', "{$lastYear}-01-01");
        $this->cashbook($erp, $nmb, 'receipt', 900_000, 'other_income', "{$lastYear}-03-10");
        $this->cashbook($erp, $nmb, 'payment', 250_000, 'rent', "{$lastYear}-03-15");
        $draft = $this->cashbook($erp, $nmb, 'payment', 10_000, 'utilities', "{$lastYear}-04-02", false);

        // Drafts dated in the month block closing it.
        $this->postJson("/api/erp/finance/periods/{$lastYear}-04/close")->assertStatus(422);
        $this->postJson("/api/erp/finance/cashbook/{$draft['id']}/cancel")->assertOk();
        $this->postJson("/api/erp/finance/periods/{$lastYear}-04/close")->assertOk();
        $this->postJson("/api/erp/finance/periods/{$lastYear}-04/close")->assertStatus(422);
        $this->postJson('/api/erp/finance/periods/'.now()->format('Y-m').'/close')->assertStatus(422);

        $late = $this->cashbook($erp, $nmb, 'payment', 5_000, 'utilities', "{$lastYear}-04-20", false);
        $this->postJson("/api/erp/finance/cashbook/{$late['id']}/post")->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'is closed'));

        app(TenantContext::class)->forCompany($erp['company'], function () use ($lastYear) {
            $this->assertTrue(PeriodLock::isClosed("{$lastYear}-04-30"));
            $this->assertFalse(PeriodLock::isClosed("{$lastYear}-05-01"));
            $this->expectException(RuntimeException::class);
            PeriodLock::assertOpen("{$lastYear}-04-01");
        });
    }

    public function test_reopening_and_closing_the_year(): void
    {
        $erp = $this->finance();
        $lastYear = now()->year - 1;
        $nmb = $this->bank($erp, 'NMB Bank', 1_000_000, 'bank', "{$lastYear}-01-01");
        $this->cashbook($erp, $nmb, 'receipt', 900_000, 'other_income', "{$lastYear}-03-10");
        $this->cashbook($erp, $nmb, 'payment', 250_000, 'rent', "{$lastYear}-03-15");

        $this->postJson("/api/erp/finance/periods/{$lastYear}-12/close")->assertOk();
        $this->postJson("/api/erp/finance/periods/{$lastYear}-12/reopen", ['reason' => 'Late invoice'])->assertOk()->assertJsonPath('data.status', 'open');
        $this->postJson("/api/erp/finance/periods/{$lastYear}-12/close")->assertOk();

        // The closing entry is dated in the closed December, by design.
        $this->postJson("/api/erp/finance/years/{$lastYear}/close")->assertOk()->assertJsonPath('data.net_profit', '650000.00');
        $this->postJson("/api/erp/finance/years/{$lastYear}/close")->assertStatus(422);
        $this->postJson('/api/erp/finance/years/'.now()->year.'/close')->assertStatus(422);
        $this->postJson("/api/erp/finance/periods/{$lastYear}-06/reopen", ['reason' => 'x x x'])->assertStatus(422);

        $tb = $this->trialBalance($erp, "{$lastYear}-12-31");
        $this->assertTrue($tb['balanced']);
        $this->assertEquals(650_000, $this->tbBalance($tb, '3100'));
        $this->assertEquals(0, $this->tbBalance($tb, '4900'));
        $this->assertEquals(0, $this->tbBalance($tb, '6300'));

        // P&L for the closed year still shows the year's result; the balance sheet still balances.
        $pl = $this->getJson("/api/erp/finance/statements/profit-and-loss?from={$lastYear}-01-01&to={$lastYear}-12-31")->json('data');
        $this->assertEquals(650_000, $pl['totals']['net_profit']);
        $bs = $this->getJson('/api/erp/finance/statements/balance-sheet')->json('data');
        $this->assertTrue($bs['balanced']);
        $this->assertEquals(0, $bs['current_earnings']);

        $periods = $this->getJson("/api/erp/finance/periods?year={$lastYear}")->assertOk()->json('data');
        $this->assertCount(12, collect($periods['months'])->where('status', 'closed'));
    }

    public function test_budget_against_actual(): void
    {
        $erp = $this->finance();
        $year = now()->year;
        $nmb = $this->bank($erp, 'NMB Bank', 5_000_000, 'bank', "{$year}-01-01");
        $this->cashbook($erp, $nmb, 'payment', 700_000, 'rent', "{$year}-01-05");
        $this->cashbook($erp, $nmb, 'payment', 800_000, 'rent', "{$year}-02-05");
        $this->cashbook($erp, $nmb, 'receipt', 1_000_000, 'other_income', "{$year}-02-07");

        $rent = $this->account($erp, 'rent')->id;
        $income = $this->account($erp, 'other_income')->id;
        $this->putJson("/api/erp/finance/budgets/{$year}", ['lines' => [
            ['account_id' => $rent, 'months' => array_fill(0, 12, 750_000)],
            ['account_id' => $income, 'months' => array_fill(0, 12, 600_000)],
        ]])->assertOk();

        // Only income and expense accounts are budgeted.
        $this->putJson("/api/erp/finance/budgets/{$year}", ['lines' => [
            ['account_id' => $this->account($erp, 'cash')->id, 'months' => array_fill(0, 12, 1)],
        ]])->assertStatus(422);

        $report = $this->getJson("/api/erp/finance/statements/budget-vs-actual?year={$year}&through_month=2")->assertOk()->json('data');
        $rentRow = collect($report['rows'])->firstWhere('account_id', $rent);
        $this->assertEquals(1_500_000, $rentRow['budget']);
        $this->assertEquals(1_500_000, $rentRow['actual']);
        $this->assertEquals(0, $rentRow['variance']);
        $incomeRow = collect($report['rows'])->firstWhere('account_id', $income);
        $this->assertEquals(-200_000, $incomeRow['variance']);

        $lines = collect($this->getJson("/api/erp/finance/budgets/{$year}")->assertOk()->json('data.lines'))->keyBy('account_id');
        $this->assertEquals(9_000_000, $lines[$rent]['total']);
        $this->assertEquals(7_200_000, $lines[$income]['total']);
    }

    public function test_permissions_are_enforced(): void
    {
        $erp = $this->finance();
        $nmb = $this->bank($erp, 'NMB Bank', 1_000_000);
        $ceo = $erp['ceo'];
        $auditor = app(TenantContext::class)->forCompany($erp['company'], fn () => User::create([
            'company_id' => $erp['company']->id, 'name' => 'Auditor', 'email' => 'auditor@maji.test',
            'password' => 'Password123!', 'role' => User::ROLE_AUDITOR, 'status' => 'active',
        ]));

        // Readers read statements but cannot move money or close periods.
        foreach ([$ceo, $auditor] as $reader) {
            $this->actingAs($reader, 'sanctum')->getJson('/api/erp/finance/statements/balance-sheet')->assertOk();
            $this->postJson('/api/erp/finance/bank-accounts', ['name' => 'X', 'type' => 'bank'])->assertForbidden();
            $this->postJson('/api/erp/finance/cashbook', [])->assertForbidden();
            $this->postJson('/api/erp/finance/periods/2025-01/close')->assertForbidden();
        }

        // The accountant records the cashbook but does not close periods or set budgets.
        $this->actingAs($erp['accountant'], 'sanctum')->getJson('/api/erp/finance/overview')->assertOk();
        $this->cashbook(['finance' => $erp['accountant'], 'company' => $erp['company']], $nmb, 'payment', 1000, 'utilities');
        $this->actingAs($erp['accountant'], 'sanctum')->postJson('/api/erp/finance/periods/2025-01/close')->assertForbidden();
        $this->putJson('/api/erp/finance/budgets/2026', ['lines' => []])->assertForbidden();

        // Others see nothing of finance.
        foreach (['storekeeper', 'employee', 'cashier'] as $who) {
            $this->actingAs($erp[$who], 'sanctum')->getJson('/api/erp/finance/overview')->assertForbidden();
            $this->getJson('/api/erp/finance/bank-accounts')->assertForbidden();
        }
    }

    public function test_another_companys_finance_records_are_invisible_and_unusable(): void
    {
        $mine = $this->finance('Maji Bora');
        $theirs = $this->finance('Zamani Freight');
        $theirBank = $this->bank($theirs, 'Their NMB', 1_000_000);
        $theirEntry = $this->cashbook($theirs, $theirBank, 'receipt', 1000, 'other_income');
        $myBank = $this->bank($mine, 'My NMB', 1_000_000);

        $this->actingAs($mine['finance'], 'sanctum');
        $this->getJson("/api/erp/finance/bank-accounts/{$theirBank['id']}")->assertNotFound();
        $this->getJson("/api/erp/finance/cashbook/{$theirEntry['id']}")->assertNotFound();
        $this->postJson("/api/erp/finance/cashbook/{$theirEntry['id']}/reverse", ['reason' => 'Mine now'])->assertNotFound();
        $this->getJson('/api/erp/finance/bank-accounts')->assertOk()->assertJsonCount(1, 'data');

        $this->postJson('/api/erp/finance/cashbook', [
            'type' => 'payment', 'entry_date' => now()->toDateString(), 'bank_account_id' => $theirBank['id'],
            'account_id' => $this->account($theirs, 'rent')->id, 'amount' => 10, 'description' => 'Sneaky',
        ])->assertStatus(422)->assertJsonValidationErrors(['bank_account_id', 'account_id']);

        $this->postJson('/api/erp/finance/transfers', [
            'transfer_date' => now()->toDateString(), 'from_bank_account_id' => $myBank['id'], 'to_bank_account_id' => $theirBank['id'], 'amount' => 10,
        ])->assertStatus(422)->assertJsonValidationErrors('to_bank_account_id');

        $bs = $this->getJson('/api/erp/finance/statements/balance-sheet')->json('data');
        $this->assertEquals(1_000_000, $bs['totals']['assets']);
    }
}
