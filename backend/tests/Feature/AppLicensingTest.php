<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Company;
use App\Models\Invoice;
use App\Models\Plan;
use App\Models\Subscription;
use App\Models\User;
use App\Services\PaymentGateway;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Database\Seeders\PlanSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * The subscription licenses apps; the company's administrator switches on any
 * of those. A company only ever runs apps that are both.
 */
class AppLicensingTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function operator(): User
    {
        return User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);
    }

    private function flexible(): Plan
    {
        return Plan::create([
            'code' => 'flexible', 'name' => 'Flexible', 'price' => 49000, 'price_yearly' => 490000,
            'price_per_module' => 25000, 'allows_module_choice' => true, 'currency' => 'TZS',
            'billing_cycle' => 'monthly', 'trial_days' => 14, 'modules' => null,
        ]);
    }

    private function register(array $extra = []): TestResponse
    {
        $this->seedPlans();

        return $this->postJson('/api/auth/register', [
            'company_name' => 'Northwind Traders',
            'business_email' => 'accounts@northwind.test',
            'name' => 'Amina Said',
            'email' => 'amina@northwind.test',
            'password' => 'Password123!',
            'password_confirmation' => 'Password123!',
        ] + $extra);
    }

    private function northwind(): Company
    {
        return Company::where('name', 'Northwind Traders')->firstOrFail();
    }

    public function test_the_seeded_plans_are_tiers_by_number_of_apps(): void
    {
        $this->seed(PlanSeeder::class);

        $this->getJson('/api/plans')
            ->assertOk()
            ->assertJsonPath('data.0.code', 'starter')
            ->assertJsonPath('data.0.apps_count', 5)
            ->assertJsonPath('data.1.code', 'business')
            ->assertJsonPath('data.1.apps_count', 10)
            ->assertJsonPath('data.3.code', 'enterprise')
            ->assertJsonPath('data.3.all_apps', true)
            ->assertJsonPath('data.3.apps_count', 12);
    }

    public function test_a_company_runs_only_apps_that_are_both_enabled_and_licensed(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $company = $t['company'];
        $company->forceFill(['modules' => ['vouchflow', 'inventory', 'sales'], 'licensed_modules' => ['vouchflow', 'sales', 'hr']])->save();

        $config = BusinessConfig::of($company->fresh());
        $this->assertSame(['vouchflow', 'sales'], $config->modules());
        $this->assertFalse($config->hasModule('inventory'));
        $this->assertFalse($config->hasModule('hr'), 'licensed but not switched on');
        $this->assertSame(['vouchflow', 'sales', 'hr'], $config->licensedModules());

        // No licence recorded means every app, as for companies from before licensing.
        $company->forceFill(['licensed_modules' => null])->save();
        $this->assertTrue(BusinessConfig::of($company->fresh())->hasModule('inventory'));
    }

    public function test_an_unlicensed_app_is_refused_by_the_module_gate(): void
    {
        $t = $this->setUpErp($this->makeTenant('Acme Trading'));
        // Switched on by setup, then the subscription stops including it.
        $this->assertContains('inventory', $t['company']->modules);
        $t['company']->forceFill(['licensed_modules' => ['vouchflow', 'sales']])->save();

        $this->actingAs($t['admin'], 'sanctum')->getJson('/api/erp/products')
            ->assertForbidden()
            ->assertJsonPath('code', 'module_disabled')
            ->assertJsonPath('message', "Inventory & warehouses is not in this company's subscription. Ask VouchFlow to add it to your plan.");
    }

    public function test_setup_refuses_an_unlicensed_app_and_the_config_lists_the_licence(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['company']->forceFill(['licensed_modules' => ['vouchflow', 'inventory', 'sales']])->save();

        $this->actingAs($t['admin'], 'sanctum')
            ->postJson('/api/erp/setup', ['business_type' => 'wholesale', 'modules' => ['inventory', 'fleet']])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'Fleet & transport is not in your subscription. Ask VouchFlow to add it to your plan.');

        $this->putJson('/api/erp/config', ['modules' => ['inventory', 'crm']])->assertUnprocessable();

        // The template's recommendation simply leaves out what is not licensed.
        $this->postJson('/api/erp/setup', ['business_type' => 'wholesale'])
            ->assertOk()
            ->assertJsonPath('data.licensed_modules', ['vouchflow', 'inventory', 'sales'])
            ->assertJsonPath('data.modules', ['vouchflow', 'inventory', 'sales']);
    }

    public function test_registering_on_a_bundle_licenses_the_ticked_apps_without_changing_the_price(): void
    {
        $this->register([
            'plan_code' => 'business',
            'modules' => ['vouchflow', 'inventory', 'sales', 'hr'],
        ])->assertCreated()
            ->assertJsonPath('company.licensed_modules', ['vouchflow', 'inventory', 'sales', 'hr']);

        $company = $this->northwind();
        // Licensed, not switched on: that is Business setup's job.
        $this->assertSame(['vouchflow'], BusinessConfig::of($company)->modules());

        $admin = User::where('email', 'amina@northwind.test')->firstOrFail();
        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/billing/subscribe', ['plan_id' => Plan::where('code', 'business')->value('id')])
            ->assertCreated()
            ->assertJsonPath('invoice.total', 249000);

        // Paying for the plan chosen keeps the apps chosen.
        $this->assertSame(['vouchflow', 'inventory', 'sales', 'hr'], $company->fresh()->licensed_modules);
    }

    public function test_registering_without_a_choice_licenses_all_the_plans_apps(): void
    {
        $this->register(['plan_code' => 'starter'])->assertCreated();

        $this->assertSame(PlanSeeder::STARTER_APPS, $this->northwind()->licensed_modules);
    }

    public function test_registering_refuses_apps_the_bundle_does_not_include(): void
    {
        $this->register(['plan_code' => 'starter', 'modules' => ['inventory', 'crm']])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'CRM is not part of the Starter plan. Choose a plan that includes it.');

        $this->assertNull(Company::where('name', 'Northwind Traders')->first());
    }

    public function test_registering_on_a_pick_your_apps_plan_charges_base_plus_each_app(): void
    {
        $this->seedPlans();
        $this->flexible();

        $this->register(['plan_code' => 'flexible', 'modules' => ['inventory', 'sales', 'crm']])->assertCreated();
        $company = $this->northwind();
        $this->assertSame(['vouchflow', 'inventory', 'sales', 'crm'], $company->licensed_modules);

        $admin = User::where('email', 'amina@northwind.test')->firstOrFail();
        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/billing/subscribe', ['plan_id' => Plan::where('code', 'flexible')->value('id')])
            ->assertCreated()
            // 49,000 + 3 apps at 25,000; VouchFlow is never charged for.
            ->assertJsonPath('invoice.total', 124000);
    }

    public function test_the_price_rule_for_a_month_and_a_year(): void
    {
        $plan = $this->flexible();
        $apps = ['vouchflow', 'inventory', 'sales'];

        $this->assertSame(99000.0, $plan->priceFor($apps, 'monthly'));
        // The yearly base plus ten months of each app.
        $this->assertSame(990000.0, $plan->priceFor($apps, 'annual'));
        // Every app the plan offers when none are named: 11 besides VouchFlow.
        $this->assertSame(49000.0 + 11 * 25000, $plan->priceFor(null, 'monthly'));

        $bundle = Plan::create(['code' => 'b', 'name' => 'B', 'price' => 100, 'billing_cycle' => 'monthly', 'price_per_module' => 999]);
        $this->assertSame(100.0, $bundle->priceFor($apps, 'monthly'));
        $this->assertSame(1000.0, $bundle->priceFor($apps, 'annual'));
    }

    public function test_the_platform_creates_a_company_with_chosen_apps(): void
    {
        $this->seedPlans();

        $this->actingAs($this->operator(), 'sanctum')
            ->postJson('/api/platform/companies', [
                'company' => ['name' => 'Kilimo Co', 'email' => 'info@kilimo.test'],
                'plan_id' => Plan::where('code', 'business')->value('id'),
                'modules' => ['inventory', 'crm'],
                'admin' => ['name' => 'Juma', 'email' => 'juma@kilimo.test', 'password' => 'Password123!'],
            ])
            ->assertCreated()
            // The operator may go beyond the plan (CRM is not in Business).
            ->assertJsonPath('data.licensed_modules', ['vouchflow', 'inventory', 'crm']);

        // Without a choice, the plan's apps.
        $this->actingAs($this->operator(), 'sanctum')
            ->postJson('/api/platform/companies', [
                'company' => ['name' => 'Pwani Co', 'email' => 'info@pwani.test'],
                'plan_id' => Plan::where('code', 'starter')->value('id'),
                'admin' => ['name' => 'Asha', 'email' => 'asha@pwani.test', 'password' => 'Password123!'],
            ])
            ->assertCreated()
            ->assertJsonPath('data.licensed_modules', PlanSeeder::STARTER_APPS);
    }

    public function test_approving_can_change_the_apps_and_the_trial_is_priced_on_them(): void
    {
        $this->seedPlans();
        $this->flexible();
        $this->register(['plan_code' => 'flexible', 'modules' => ['inventory', 'sales', 'crm']])->assertCreated();
        $company = $this->northwind();

        $this->actingAs($this->operator(), 'sanctum')
            ->postJson("/api/platform/companies/{$company->id}/approve", ['modules' => ['inventory']])
            ->assertOk()
            ->assertJsonPath('data.licensed_modules', ['vouchflow', 'inventory']);

        $subscription = Subscription::withoutGlobalScopes()->where('company_id', $company->id)->where('status', 'trialing')->firstOrFail();
        $this->assertSame(74000.0, (float) $subscription->amount);
        $this->assertTrue(AuditLog::withoutGlobalScopes()->where('action', 'platform.company_modules_updated')->exists());
    }

    public function test_changing_to_a_bundle_licenses_the_bundles_apps(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $company = $t['company'];

        app(TenantContext::class)->forCompany($company, fn () => app(PaymentGateway::class)
            ->subscribe($company, Plan::where('code', 'starter')->firstOrFail(), 'monthly'));

        $this->assertSame(PlanSeeder::STARTER_APPS, $company->fresh()->licensed_modules);

        $this->actingAs($this->operator(), 'sanctum')
            ->postJson("/api/platform/companies/{$company->id}/change-plan", ['plan_id' => Plan::where('code', 'enterprise')->value('id')])
            ->assertOk();

        $this->assertNull($company->fresh()->licensed_modules, 'every app');
        $this->assertSame(0, Invoice::withoutGlobalScopes()->where('company_id', $company->id)->count());
    }

    public function test_a_plan_can_offer_every_app_or_let_the_customer_pick(): void
    {
        $res = $this->actingAs($this->operator(), 'sanctum')
            ->postJson('/api/platform/plans', [
                'code' => 'flex', 'name' => 'Flex', 'price' => 49000, 'billing_cycle' => 'monthly',
                'modules' => null, 'allows_module_choice' => true, 'price_per_module' => 25000,
            ])
            ->assertCreated()
            ->assertJsonPath('data.all_apps', true)
            ->assertJsonPath('data.allows_module_choice', true)
            ->assertJsonPath('data.price_per_module', 25000);

        $this->assertNull(Plan::find($res->json('data.id'))->modules);
    }
}
