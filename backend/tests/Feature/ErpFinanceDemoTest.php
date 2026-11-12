<?php

namespace Tests\Feature;

use App\Models\Erp\Finance\AssetDepreciationRun;
use App\Models\Erp\Finance\BankAccount;
use App\Models\Erp\Finance\BankReconciliation;
use App\Models\Erp\Finance\CashbookEntry;
use App\Models\Erp\Finance\ClosedPeriod;
use App\Models\Erp\Finance\FixedAsset;
use App\Models\Erp\JournalEntry;
use App\Support\TenantContext;
use Database\Seeders\Erp\Step70FinanceSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/** The finance demo seeds a working set of books, and running it again adds nothing. */
class ErpFinanceDemoTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    public function test_the_demo_books_balance_and_the_seeder_is_idempotent(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Watercom Demo'), 'beverage');
        $company = $erp['company'];
        $census = fn () => app(TenantContext::class)->forCompany($company, fn () => [
            'banks' => BankAccount::count(), 'cashbook' => CashbookEntry::count(), 'journals' => JournalEntry::count(),
            'assets' => FixedAsset::count(), 'runs' => AssetDepreciationRun::count(), 'recs' => BankReconciliation::count(),
            'closed' => ClosedPeriod::count(),
        ]);

        app(TenantContext::class)->forCompany($company, fn () => $this->seed(Step70FinanceSeeder::class));
        $first = $census();
        app(TenantContext::class)->forCompany($company->fresh(), fn () => $this->seed(Step70FinanceSeeder::class));
        $this->assertSame($first, $census());

        $this->assertSame(3, $first['banks']);
        $this->assertSame(6, $first['runs']);
        $this->assertSame(4, $first['closed']);
        $this->assertContains('assets', $company->fresh()->modules);

        $this->actingAs($erp['admin']->fresh(), 'sanctum');
        $this->assertTrue($this->getJson('/api/erp/trial-balance')->json('data.balanced'));
        $this->assertTrue($this->getJson('/api/erp/finance/statements/balance-sheet')->json('data.balanced'));
        $this->assertTrue($this->getJson('/api/erp/finance/statements/cash-flow?from='.now()->subMonths(7)->startOfMonth()->toDateString())->json('data.reconciles'));

        $recs = collect($this->getJson('/api/erp/finance/reconciliations')->json('data'));
        $this->assertSame(['open', 'completed'], $recs->pluck('status')->all());
        $open = $this->getJson("/api/erp/finance/reconciliations/{$recs->first()['id']}")->json('data');
        $this->assertSame(1, $open['summary']['unmatched_statement_count']);
        $this->assertEquals(1_850_000, $open['summary']['outstanding_payments']);
        $this->assertEquals(0, $open['summary']['difference']);

        $this->getJson('/api/erp/finance/overview')->assertOk()->assertJsonPath('data.drafts.cashbook', 2);
        $this->getJson('/api/erp/assets/overview')->assertOk()->assertJsonPath('data.counts.disposed', 1)->assertJsonPath('data.counts.draft', 1);
        $this->getJson('/api/erp/finance/statements/budget-vs-actual')->assertOk()->assertJsonPath('data.has_budget', true);
    }
}
