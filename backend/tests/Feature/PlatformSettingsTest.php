<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Company;
use App\Models\Plan;
use App\Models\User;
use App\Services\PaymentGateway;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** Platform-wide defaults are stored, audited and used. */
class PlatformSettingsTest extends TestCase
{
    use RefreshDatabase;

    private function operator(): User
    {
        return User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);
    }

    public function test_settings_are_saved_validated_and_audited(): void
    {
        $op = $this->operator();

        $this->actingAs($op, 'sanctum')->getJson('/api/platform/settings')
            ->assertOk()->assertJsonPath('data.trial_days', 14)->assertJsonPath('data.default_currency', 'TZS');

        $this->actingAs($op, 'sanctum')->putJson('/api/platform/settings', [
            'trial_days' => 21, 'support_email' => 'help@vouchflow.test', 'default_currency' => 'kes',
        ])->assertOk()->assertJsonPath('data.trial_days', 21)->assertJsonPath('data.default_currency', 'KES');

        $this->actingAs($op, 'sanctum')->getJson('/api/platform/settings')
            ->assertJsonPath('data.support_email', 'help@vouchflow.test');

        $this->actingAs($op, 'sanctum')->putJson('/api/platform/settings', ['trial_days' => 999, 'support_email' => 'nope'])
            ->assertJsonValidationErrors(['trial_days', 'support_email']);

        $this->assertSame(1, AuditLog::where('action', 'platform.settings_updated')->count());
    }

    public function test_the_default_trial_applies_when_a_plan_names_none(): void
    {
        $this->actingAs($this->operator(), 'sanctum')->putJson('/api/platform/settings', ['trial_days' => 30])->assertOk();

        $plan = Plan::create(['code' => 'free', 'name' => 'Free', 'price' => 0, 'currency' => 'TZS', 'billing_cycle' => 'monthly', 'trial_days' => 0]);
        $company = Company::create(['name' => 'New Co', 'slug' => 'new-co', 'email' => 'n@n.test', 'status' => 'pending']);

        app(PaymentGateway::class)->startTrial($company, $plan);

        $this->assertSame(now()->addDays(30)->toDateString(), $company->fresh()->trial_ends_at->toDateString());
    }
}
