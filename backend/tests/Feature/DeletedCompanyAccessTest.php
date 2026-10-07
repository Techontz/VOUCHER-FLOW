<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Deleting a company soft-deletes it. Its people used to be able to sign in
 * and then met "This account is not attached to a company." on every page.
 */
class DeletedCompanyAccessTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    public function test_a_deleted_companys_people_cannot_sign_in(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['company']->delete();

        $this->postJson('/api/auth/login', [
            'email' => $t['admin']->email,
            'password' => 'Password123!',
        ])
            ->assertStatus(422)
            ->assertJsonPath('errors.email.0', 'This company account is no longer available. Contact support@vouchflow.co.tz.');
    }

    public function test_an_open_session_is_ended_when_its_company_is_deleted(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $token = $t['admin']->createToken('web')->plainTextToken;
        $t['company']->delete();

        $this->withToken($token)->getJson('/api/dashboard')
            ->assertStatus(401)
            ->assertJsonPath('code', 'company_unavailable');

        $this->assertSame(0, $t['admin']->tokens()->count());
    }
}
