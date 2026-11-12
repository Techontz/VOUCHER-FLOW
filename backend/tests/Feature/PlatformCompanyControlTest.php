<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/** The operator switches a company's modules and gives it more time. */
class PlatformCompanyControlTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function operator(): User
    {
        return User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);
    }

    public function test_the_apps_in_a_subscription_are_set_and_audited(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $c = $t['company'];
        $c->forceFill(['modules' => ['vouchflow', 'inventory', 'sales']])->save();

        // Every app was licensed; the operator keeps inventory and fleet.
        $this->actingAs($this->operator(), 'sanctum')
            ->putJson("/api/platform/companies/{$c->id}/modules", ['modules' => ['inventory', 'fleet']])
            ->assertOk()
            ->assertJsonPath('licensed_modules', ['vouchflow', 'inventory', 'fleet'])
            ->assertJsonPath('modules', ['vouchflow', 'inventory']);

        $this->assertSame(['vouchflow', 'inventory', 'fleet'], $c->fresh()->licensed_modules);
        $this->assertSame(['vouchflow', 'inventory'], $c->fresh()->modules, 'sales is no longer licensed, so it is switched off');

        $log = AuditLog::where('action', 'platform.company_modules_updated')->latest('id')->first();
        $this->assertNotNull($log);
        $this->assertSame($c->id, (int) $log->company_id);
        $this->assertSame(['vouchflow', 'inventory', 'fleet'], $log->after['licensed_modules']);
        $this->assertStringContainsString('removed: sales', $log->description);

        // Licensing an app again switches it on straight away.
        $this->actingAs($this->operator(), 'sanctum')
            ->putJson("/api/platform/companies/{$c->id}/modules", ['modules' => ['inventory', 'fleet', 'crm']])
            ->assertOk()
            ->assertJsonPath('modules', ['vouchflow', 'inventory', 'crm']);
    }

    public function test_payment_vouchers_stay_on_even_when_everything_is_switched_off(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $c = $t['company'];
        $c->forceFill(['modules' => ['vouchflow', 'sales']])->save();

        $this->actingAs($this->operator(), 'sanctum')
            ->putJson("/api/platform/companies/{$c->id}/modules", ['modules' => []])
            ->assertOk()
            ->assertJsonPath('licensed_modules', ['vouchflow'])
            ->assertJsonPath('modules', ['vouchflow']);
    }

    public function test_unknown_modules_are_rejected(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($this->operator(), 'sanctum')
            ->putJson("/api/platform/companies/{$t['company']->id}/modules", ['modules' => ['inventory', 'casino']])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('modules.1');

        $this->assertSame(0, AuditLog::where('action', 'platform.company_modules_updated')->count());
    }

    public function test_the_company_detail_lists_its_modules_and_the_catalogue(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['company']->forceFill(['modules' => ['inventory']])->save();

        $this->actingAs($this->operator(), 'sanctum')
            ->getJson("/api/platform/companies/{$t['company']->id}")
            ->assertOk()
            ->assertJsonPath('modules', ['vouchflow', 'inventory'])
            ->assertJsonPath('module_catalogue.0.key', 'vouchflow')
            ->assertJsonStructure(['usage' => ['users' => ['used', 'limit', 'percent'], 'vouchers_this_month', 'departments']]);
    }

    public function test_a_trial_is_extended_by_days_and_audited(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $c = $t['company'];
        $c->forceFill(['status' => 'trial'])->save();
        $end = $c->fresh()->trial_ends_at;

        $this->actingAs($this->operator(), 'sanctum')
            ->postJson("/api/platform/companies/{$c->id}/extend", ['days' => 10])
            ->assertOk();

        $fresh = $c->fresh();
        $this->assertSame($end->copy()->addDays(10)->toDateString(), $fresh->trial_ends_at->toDateString());
        $this->assertSame($fresh->trial_ends_at->toDateString(), $fresh->current_period_end->toDateString());

        $sub = $fresh->subscriptions()->withoutGlobalScopes()->where('status', 'trialing')->first();
        $this->assertSame($fresh->trial_ends_at->toDateString(), $sub->trial_ends_at->toDateString());
        $this->assertTrue(AuditLog::where('action', 'platform.subscription_extended')->exists());
    }

    public function test_extending_refuses_an_earlier_date_and_a_pending_company(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $c = $t['company'];
        $op = $this->operator();

        $this->actingAs($op, 'sanctum')
            ->postJson("/api/platform/companies/{$c->id}/extend", ['until' => now()->addDay()->toDateString()])
            ->assertUnprocessable();

        $c->forceFill(['status' => 'pending'])->save();
        $this->actingAs($op, 'sanctum')
            ->postJson("/api/platform/companies/{$c->id}/extend", ['days' => 5])
            ->assertUnprocessable();

        $this->actingAs($op, 'sanctum')
            ->postJson("/api/platform/companies/{$c->id}/extend", [])
            ->assertJsonValidationErrors(['days', 'until']);
    }

    public function test_the_company_list_filters_expired_and_sorts(): void
    {
        $a = $this->makeTenant('Acme Trading');
        $b = $this->makeTenant('Bahari Foods');
        $b['company']->forceFill(['status' => 'trial', 'trial_ends_at' => now()->subDay()])->save();
        $op = $this->operator();

        $this->actingAs($op, 'sanctum')->getJson('/api/platform/companies?status=expired')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Bahari Foods');

        $this->makeVoucher($b);
        $this->actingAs($op, 'sanctum')->getJson('/api/platform/companies?sort=vouchers')
            ->assertOk()->assertJsonPath('data.0.name', 'Bahari Foods');
        $this->actingAs($op, 'sanctum')->getJson('/api/platform/companies?sort=newest')
            ->assertOk()->assertJsonPath('data.0.id', $b['company']->id);
    }
}
