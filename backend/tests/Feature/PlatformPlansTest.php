<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Plan;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/** The plan editor: create, edit, order, hide, archive and delete. */
class PlatformPlansTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function operator(): User
    {
        return User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);
    }

    private function payload(array $overrides = []): array
    {
        return [
            'code' => 'growth', 'name' => 'Growth', 'price' => 150000, 'price_yearly' => 1400000,
            'currency' => 'tzs', 'billing_cycle' => 'monthly', 'max_users' => 25, 'max_vouchers_per_month' => null,
            'max_departments' => 10, 'max_approval_levels' => 3, 'features' => ['25 users', ' ', 'Reports'],
            'modules' => ['inventory', 'sales'], 'is_featured' => true, ...$overrides,
        ];
    }

    public function test_a_plan_is_created_with_prices_limits_features_and_modules(): void
    {
        $this->seedPlans();

        $res = $this->actingAs($this->operator(), 'sanctum')
            ->postJson('/api/platform/plans', $this->payload())
            ->assertCreated()
            ->assertJsonPath('data.price_yearly', 1400000)
            ->assertJsonPath('data.yearly_price', 1400000)
            ->assertJsonPath('data.currency', 'TZS')
            ->assertJsonPath('data.features', ['25 users', 'Reports'])
            ->assertJsonPath('data.modules', ['vouchflow', 'inventory', 'sales'])
            ->assertJsonPath('data.is_featured', true);

        // A new plan goes to the end of the order.
        $this->assertSame((int) Plan::max('sort_order'), $res->json('data.sort_order'));
        $this->assertTrue(AuditLog::where('action', 'platform.plan_created')->exists());
    }

    public function test_unknown_modules_are_rejected(): void
    {
        $this->actingAs($this->operator(), 'sanctum')
            ->postJson('/api/platform/plans', $this->payload(['modules' => ['casino']]))
            ->assertJsonValidationErrors('modules.0');
    }

    public function test_reordering_persists_and_the_public_pricing_follows_it(): void
    {
        $this->seedPlans();
        $ids = Plan::orderBy('sort_order')->pluck('id')->all();
        $reversed = array_reverse($ids);

        $this->actingAs($this->operator(), 'sanctum')
            ->postJson('/api/platform/plans/reorder', ['ids' => $reversed])
            ->assertOk()
            ->assertJsonPath('data.0.id', $reversed[0]);

        $this->assertSame($reversed, Plan::orderBy('sort_order')->pluck('id')->all());
        $this->assertTrue(AuditLog::where('action', 'platform.plans_reordered')->exists());

        $public = $this->getJson('/api/plans')->assertOk()->json('data');
        $expected = Plan::whereIn('id', $reversed)->where('is_active', true)->where('is_public', true)
            ->orderBy('sort_order')->pluck('id')->all();
        $this->assertSame($expected, array_column($public, 'id'));
        $this->assertSame($reversed[0], $public[0]['id']);
    }

    public function test_reordering_must_name_every_plan(): void
    {
        $this->seedPlans();

        $this->actingAs($this->operator(), 'sanctum')
            ->postJson('/api/platform/plans/reorder', ['ids' => [Plan::first()->id]])
            ->assertUnprocessable();
    }

    public function test_hidden_and_archived_plans_are_left_off_the_public_pricing(): void
    {
        $this->seedPlans();
        $op = $this->operator();
        [$first, $second] = Plan::orderBy('sort_order')->take(2)->get()->all();

        $this->actingAs($op, 'sanctum')
            ->putJson("/api/platform/plans/{$first->id}", [...$first->only(['code', 'name', 'price', 'billing_cycle']), 'is_public' => false])
            ->assertOk()->assertJsonPath('data.is_public', false);
        $this->actingAs($op, 'sanctum')
            ->putJson("/api/platform/plans/{$second->id}", [...$second->only(['code', 'name', 'price', 'billing_cycle']), 'is_active' => false])
            ->assertOk();

        $ids = array_column($this->getJson('/api/plans')->json('data'), 'id');
        $this->assertNotContains($first->id, $ids);
        $this->assertNotContains($second->id, $ids);
        $this->assertNotEmpty($ids);
    }

    public function test_a_plan_in_use_cannot_be_deleted_but_an_unused_one_can(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $op = $this->operator();

        $this->actingAs($op, 'sanctum')
            ->deleteJson("/api/platform/plans/{$t['company']->plan_id}")
            ->assertUnprocessable();
        $this->assertNotNull(Plan::find($t['company']->plan_id));

        $unused = Plan::create(['code' => 'spare', 'name' => 'Spare', 'price' => 1, 'billing_cycle' => 'monthly']);
        $this->actingAs($op, 'sanctum')->deleteJson("/api/platform/plans/{$unused->id}")->assertOk();
        $this->assertNull(Plan::find($unused->id));
    }

    public function test_a_plan_only_in_billing_history_cannot_be_deleted(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $old = $t['company']->plan_id;
        $t['company']->forceFill(['plan_id' => null])->save();

        $this->actingAs($this->operator(), 'sanctum')
            ->deleteJson("/api/platform/plans/{$old}")
            ->assertUnprocessable();
    }
}
