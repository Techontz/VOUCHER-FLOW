<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * An administrator can open, edit and remove the people in their own company.
 * The routes once bound no user at all, so every one of these answered 404.
 */
class EmployeeManagementTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    public function test_an_admin_can_open_a_person(): void
    {
        $acme = $this->makeTenant('Acme Trading');

        $this->actingAs($acme['admin'], 'sanctum')
            ->getJson("/api/employees/{$acme['employee']->id}")
            ->assertOk()
            ->assertJsonPath('data.id', $acme['employee']->id);
    }

    public function test_an_admin_can_edit_a_person(): void
    {
        $acme = $this->makeTenant('Acme Trading');

        $this->actingAs($acme['admin'], 'sanctum')
            ->putJson("/api/employees/{$acme['employee']->id}", [
                'job_title' => 'Fleet driver',
                'role' => 'hod',
            ])
            ->assertOk();

        $fresh = $acme['employee']->fresh();
        $this->assertSame('Fleet driver', $fresh->job_title);
        $this->assertSame('hod', $fresh->role);
    }

    public function test_an_admin_can_remove_a_person(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $id = $acme['employee']->id;

        $this->actingAs($acme['admin'], 'sanctum')
            ->deleteJson("/api/employees/{$id}")
            ->assertOk();

        $this->actingAs($acme['admin'], 'sanctum')
            ->getJson("/api/employees/{$id}")
            ->assertNotFound();
    }

    public function test_an_admin_cannot_remove_their_own_account(): void
    {
        $acme = $this->makeTenant('Acme Trading');

        $this->actingAs($acme['admin'], 'sanctum')
            ->deleteJson("/api/employees/{$acme['admin']->id}")
            ->assertStatus(422)
            ->assertJsonPath('message', 'You cannot remove your own account.');
    }
}
