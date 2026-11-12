<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\Invoice;
use App\Models\Plan;
use App\Models\User;
use App\Models\Voucher;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;
use Tests\TestSupport;

/** The platform overview's figures are the sums of the rows behind them. */
class PlatformAnalyticsTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function operator(): User
    {
        return User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);
    }

    private function invoice(Company $company, float $total, string $status, ?Carbon $paidAt, ?Carbon $start = null, ?Carbon $end = null): Invoice
    {
        static $n = 0;
        $n++;

        return Invoice::create([
            'company_id' => $company->id, 'number' => "INV-T-{$n}", 'description' => 'Test',
            'amount' => $total, 'total' => $total, 'currency' => 'TZS', 'status' => $status,
            'paid_at' => $paidAt, 'issued_at' => $paidAt ?? now(),
            'period_start' => $start, 'period_end' => $end,
        ]);
    }

    public function test_the_figures_match_the_seeded_rows(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-11-15 10:00:00'));

        $a = $this->makeTenant('Acme Trading');
        $b = $this->makeTenant('Bahari Foods');

        // Two more companies: one waiting for approval, one suspended this week,
        // one whose trial ran out five days ago.
        $plan = Plan::where('code', 'starter')->first();
        Company::create(['name' => 'Pending Ltd', 'slug' => 'pending-ltd', 'email' => 'p@p.test', 'status' => 'pending', 'plan_id' => $plan->id]);
        Company::create(['name' => 'Gone Ltd', 'slug' => 'gone-ltd', 'email' => 'g@g.test', 'status' => 'suspended', 'plan_id' => $plan->id]);
        Company::create(['name' => 'Lapsed Ltd', 'slug' => 'lapsed-ltd', 'email' => 'l@l.test', 'status' => 'trial',
            'trial_ends_at' => now()->subDays(5), 'current_period_end' => now()->subDays(5)]);

        $a['company']->forceFill(['modules' => ['vouchflow', 'inventory', 'sales']])->save();
        $b['company']->forceFill(['modules' => ['vouchflow', 'inventory']])->save();

        // Paid this month for this month; paid in September for September; a
        // year paid in October from 1 October; one pending that must not count.
        $this->invoice($a['company'], 100000, 'paid', Carbon::parse('2026-11-02'), Carbon::parse('2026-11-01'), Carbon::parse('2026-12-01'));
        $this->invoice($b['company'], 50000, 'paid', Carbon::parse('2026-09-03'), Carbon::parse('2026-09-01'), Carbon::parse('2026-10-01'));
        $this->invoice($b['company'], 1200000, 'paid', Carbon::parse('2026-10-01'), Carbon::parse('2026-10-01'), Carbon::parse('2027-10-01'));
        $this->invoice($a['company'], 999999, 'pending', null);

        $this->makeVoucher($a, null, 300000);
        $this->makeVoucher($a, null, 200000);
        $paid = $this->makeVoucher($b, null, 50000);
        Voucher::query()->withoutGlobalScopes()->whereKey($paid->id)->update(['status' => 'paid', 'paid_at' => now()]);

        $data = $this->actingAs($this->operator(), 'sanctum')
            ->getJson('/api/platform/analytics')
            ->assertOk()
            ->json('data');

        $this->assertCount(12, $data['months']);
        $this->assertSame('2025-12', $data['months'][0]);
        $this->assertSame('2026-11', $data['months'][11]);

        $revenue = collect($data['revenue_by_month'])->pluck('value', 'month');
        $this->assertEquals(100000, $revenue['2026-11']);
        $this->assertEquals(1200000, $revenue['2026-10']);
        $this->assertEquals(50000, $revenue['2026-09']);
        $this->assertEquals(0, $revenue['2026-08']);
        $this->assertEquals(1350000, $data['kpis']['revenue_12m']);
        $this->assertEquals(100000, $data['kpis']['revenue_this_month']);
        $this->assertEquals(1200000, $data['kpis']['revenue_last_month']);

        // The year is recognised a month at a time (days of the month over 365).
        $mrr = collect($data['mrr_by_month'])->pluck('value', 'month');
        $this->assertEqualsWithDelta(50000, $mrr['2026-09'], 0.01);
        $this->assertEqualsWithDelta(1200000 * 31 / 365, $mrr['2026-10'], 0.01);
        $this->assertEqualsWithDelta(100000 + 1200000 * 30 / 365, $mrr['2026-11'], 0.01);

        $this->assertSame(['pending' => 1, 'trial' => 0, 'active' => 2, 'past_due' => 0, 'suspended' => 1, 'expired' => 1, 'cancelled' => 0], $data['companies_by_status']);
        $this->assertSame(5, $data['kpis']['companies']);
        $this->assertSame(1, $data['kpis']['pending_approvals']);
        $this->assertSame('Pending Ltd', $data['pending'][0]['name']);

        $byPlan = collect($data['companies_by_plan'])->pluck('count', 'name');
        $this->assertSame(2, $byPlan['Business']);
        $this->assertSame(2, $byPlan['Starter']);
        $this->assertSame(1, $byPlan['No plan']);

        $signups = collect($data['signups_by_month'])->pluck('value', 'month');
        $this->assertEquals(5, $signups['2026-11']);

        // Seven people in each tenant from makeTenant (admin and six roles).
        $this->assertSame(14, $data['kpis']['users']);
        $this->assertSame(2, $data['users_by_role']['company_admin']);
        $this->assertSame(2, $data['users_by_role']['employee']);

        $vouchers = collect($data['vouchers_by_month'])->keyBy('month');
        $this->assertSame(3, $vouchers['2026-11']['created']);
        $this->assertEquals(550000, $vouchers['2026-11']['created_value']);
        $this->assertSame(1, $vouchers['2026-11']['paid']);
        $this->assertEquals(50000, $vouchers['2026-11']['paid_value']);
        $this->assertSame(3, $data['kpis']['vouchers']);
        $this->assertEquals(550000, $data['kpis']['vouchers_value']);

        $adoption = collect($data['module_adoption'])->keyBy('key');
        $this->assertSame(5, $adoption['vouchflow']['count']);
        $this->assertSame(2, $adoption['inventory']['count']);
        $this->assertSame(1, $adoption['sales']['count']);
        $this->assertSame(0, $adoption['fleet']['count']);

        // Both tenants' trials end in 14 days.
        $this->assertCount(2, $data['expiring']);

        // Suspended this month and expired five days ago; four live companies.
        $this->assertSame(2, $data['churn']['count']);
        $this->assertEquals(50.0, $data['churn']['rate']);

        $this->assertSame('Acme Trading', $data['top_companies'][0]['name']);
        $this->assertSame(2, $data['top_companies'][0]['vouchers']);
        $this->assertEquals(500000, $data['top_companies'][0]['value']);
    }
}
