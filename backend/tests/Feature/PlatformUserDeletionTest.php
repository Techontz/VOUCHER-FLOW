<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * The platform operator can delete accounts one at a time or several at once,
 * and deleting a company takes its people with it.
 */
class PlatformUserDeletionTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function operator(): User
    {
        return User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);
    }

    public function test_one_user_can_be_deleted(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['employee']->createToken('web');

        $this->actingAs($this->operator(), 'sanctum')
            ->deleteJson("/api/platform/users/{$t['employee']->id}")
            ->assertOk();

        $this->assertSoftDeleted($t['employee']);
        $this->assertSame(0, $t['employee']->tokens()->count());
    }

    public function test_several_users_can_be_deleted_and_those_that_must_stay_are_named(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $operator = $this->operator();

        $response = $this->actingAs($operator, 'sanctum')
            ->postJson('/api/platform/users/bulk-delete', [
                'ids' => [$t['employee']->id, $t['hod']->id, $t['admin']->id, $operator->id],
            ])
            ->assertOk()
            ->assertJsonPath('deleted', 2);

        $this->assertEqualsCanonicalizing(
            [$t['admin']->id, $operator->id],
            array_column($response->json('skipped'), 'id'),
        );
        $this->assertSoftDeleted($t['employee']);
        $this->assertSoftDeleted($t['hod']);
        $this->assertNotSoftDeleted($t['admin']);
    }

    public function test_the_last_company_admin_cannot_be_deleted_alone(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($this->operator(), 'sanctum')
            ->deleteJson("/api/platform/users/{$t['admin']->id}")
            ->assertStatus(422);
    }

    public function test_people_left_by_an_earlier_company_deletion_can_be_deleted(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['company']->delete();

        $this->actingAs($this->operator(), 'sanctum')
            ->deleteJson("/api/platform/users/{$t['admin']->id}")
            ->assertOk();
    }

    public function test_deleting_a_company_deletes_its_people(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($this->operator(), 'sanctum')
            ->deleteJson("/api/platform/companies/{$t['company']->id}")
            ->assertOk();

        $this->assertSoftDeleted($t['admin']);
        $this->assertSoftDeleted($t['employee']);
    }

    public function test_only_the_operator_may_delete(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['admin'], 'sanctum')
            ->deleteJson("/api/platform/users/{$t['employee']->id}")
            ->assertForbidden();
    }
}
