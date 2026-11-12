<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\User;
use App\Notifications\InvitationNotification;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;
use Tests\TestSupport;

/** Suspending, reactivating, re-roling and inviting accounts across tenants. */
class PlatformUserControlTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function operator(string $email = 'super@vouchflow.test', string $status = 'active'): User
    {
        return User::create([
            'company_id' => null, 'name' => 'Operator '.$email, 'email' => $email,
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => $status,
        ]);
    }

    public function test_a_user_is_suspended_signed_out_and_reactivated(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['employee']->createToken('web');
        $op = $this->operator();

        $this->actingAs($op, 'sanctum')->putJson("/api/platform/users/{$t['employee']->id}", ['status' => 'suspended'])
            ->assertOk()->assertJsonPath('data.status', 'suspended');
        $this->assertSame(0, $t['employee']->tokens()->count());

        $this->actingAs($op, 'sanctum')->putJson("/api/platform/users/{$t['employee']->id}", ['status' => 'active'])
            ->assertOk()->assertJsonPath('data.status', 'active');

        $this->assertSame(2, AuditLog::where('action', 'platform.user_updated')->count());
    }

    public function test_the_operator_cannot_act_on_themselves(): void
    {
        $op = $this->operator();
        $this->operator('second@vouchflow.test');

        $this->actingAs($op, 'sanctum')->putJson("/api/platform/users/{$op->id}", ['status' => 'suspended'])
            ->assertUnprocessable();
        $this->assertSame('active', $op->fresh()->status);
    }

    public function test_the_last_active_operator_cannot_be_suspended(): void
    {
        // The caller is an operator whose own account is not active, so the
        // target is the only active one left.
        $caller = $this->operator('caller@vouchflow.test', 'invited');
        $last = $this->operator('last@vouchflow.test');

        $this->actingAs($caller, 'sanctum')->putJson("/api/platform/users/{$last->id}", ['status' => 'suspended'])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'The platform must keep at least one active operator.');

        $other = $this->operator('other@vouchflow.test');
        $this->actingAs($other, 'sanctum')->putJson("/api/platform/users/{$last->id}", ['status' => 'suspended'])
            ->assertOk();
    }

    public function test_an_operator_cannot_be_demoted_and_nobody_is_promoted_to_operator(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $op = $this->operator();
        $peer = $this->operator('peer@vouchflow.test');

        $this->actingAs($op, 'sanctum')->putJson("/api/platform/users/{$peer->id}", ['role' => 'employee'])
            ->assertUnprocessable();
        $this->assertSame(User::ROLE_SUPER_ADMIN, $peer->fresh()->role);

        $this->actingAs($op, 'sanctum')->putJson("/api/platform/users/{$t['employee']->id}", ['role' => 'super_admin'])
            ->assertUnprocessable();
        $this->assertSame(User::ROLE_EMPLOYEE, $t['employee']->fresh()->role);
    }

    public function test_a_role_changes_within_the_company_vocabulary(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $op = $this->operator();

        $this->actingAs($op, 'sanctum')->putJson("/api/platform/users/{$t['employee']->id}", ['role' => 'storekeeper'])
            ->assertOk()->assertJsonPath('data.role', 'storekeeper');

        $this->actingAs($op, 'sanctum')->putJson("/api/platform/users/{$t['employee']->id}", ['role' => 'wizard'])
            ->assertUnprocessable();

        $this->actingAs($op, 'sanctum')->getJson("/api/platform/users/roles?company_id={$t['company']->id}")
            ->assertOk()->assertJsonFragment(['key' => 'storekeeper']);
    }

    public function test_the_last_company_admin_keeps_the_role_and_stays_active(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $op = $this->operator();

        $this->actingAs($op, 'sanctum')->putJson("/api/platform/users/{$t['admin']->id}", ['role' => 'employee'])
            ->assertUnprocessable();
        $this->actingAs($op, 'sanctum')->putJson("/api/platform/users/{$t['admin']->id}", ['status' => 'suspended'])
            ->assertUnprocessable();

        $t['ceo']->forceFill(['role' => User::ROLE_COMPANY_ADMIN])->save();
        $this->actingAs($op, 'sanctum')->putJson("/api/platform/users/{$t['admin']->id}", ['role' => 'employee'])
            ->assertOk();
    }

    public function test_bulk_suspend_skips_who_must_stay(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $op = $this->operator();

        $res = $this->actingAs($op, 'sanctum')->postJson('/api/platform/users/bulk-status', [
            'ids' => [$t['employee']->id, $t['hod']->id, $t['admin']->id, $op->id],
            'status' => 'suspended',
        ])->assertOk()->assertJsonPath('updated', 2);

        $this->assertEqualsCanonicalizing([$t['admin']->id, $op->id], array_column($res->json('skipped'), 'id'));
        $this->assertSame('suspended', $t['employee']->fresh()->status);
        $this->assertSame('active', $t['admin']->fresh()->status);

        $this->actingAs($op, 'sanctum')->postJson('/api/platform/users/bulk-status', [
            'ids' => [$t['employee']->id, $t['hod']->id], 'status' => 'active',
        ])->assertOk()->assertJsonPath('updated', 2);
        $this->assertSame('active', $t['hod']->fresh()->status);
    }

    public function test_a_password_link_is_sent_with_the_existing_invitation_mechanism(): void
    {
        Notification::fake();
        $t = $this->makeTenant('Acme Trading');
        $op = $this->operator();

        $res = $this->actingAs($op, 'sanctum')->postJson("/api/platform/users/{$t['employee']->id}/invite")
            ->assertOk()->assertJsonPath('invitation_sent', true);

        $this->assertStringContainsString('/invite?token=', $res->json('invitation_url'));
        Notification::assertSentTo($t['employee'], InvitationNotification::class);
        $this->assertNotNull($t['employee']->fresh()->invitation_token);
        $this->assertTrue(AuditLog::where('action', 'platform.user_invited')->exists());

        // Platform operators use the sign-in page's reset instead.
        $peer = $this->operator('peer@vouchflow.test');
        $this->actingAs($op, 'sanctum')->postJson("/api/platform/users/{$peer->id}/invite")->assertUnprocessable();
    }
}
