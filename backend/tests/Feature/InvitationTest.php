<?php

namespace Tests\Feature;

use App\Models\User;
use App\Notifications\InvitationNotification;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * A person an administrator adds is emailed a link to choose their own
 * password. They used to get nothing at all: a random password they were
 * never told, and no way in.
 */
class InvitationTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function invite(array $tenant, string $email = 'new.person@acme-trading.test'): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($tenant['admin'], 'sanctum')->postJson('/api/employees', [
            'name' => 'New Person',
            'email' => $email,
            'role' => 'employee',
            'send_invitation' => true,
        ]);
    }

    private function tokenFrom(string $url): string
    {
        parse_str((string) parse_url($url, PHP_URL_QUERY), $query);

        return (string) $query['token'];
    }

    public function test_an_invited_person_is_emailed_a_link_and_can_set_their_password(): void
    {
        Notification::fake();
        $t = $this->makeTenant('Acme Trading');

        $response = $this->invite($t)->assertCreated()
            ->assertJsonPath('invitation_sent', true)
            ->assertJsonPath('data.status', 'invited');

        $user = User::where('email', 'new.person@acme-trading.test')->firstOrFail();
        $url = null;
        Notification::assertSentTo($user, InvitationNotification::class, function (InvitationNotification $n) use (&$url) {
            $url = $n->url;

            return true;
        });
        $this->assertSame($url, $response->json('invitation_url'));
        $token = $this->tokenFrom($url);

        // Only a hash is kept.
        $this->assertNotSame($token, $user->fresh()->invitation_token);

        $this->getJson("/api/auth/invitation/{$token}")
            ->assertOk()
            ->assertJsonPath('email', 'new.person@acme-trading.test')
            ->assertJsonPath('company', 'Acme Trading');

        $this->postJson('/api/auth/invitation/accept', [
            'token' => $token,
            'password' => 'MyOwnPass1',
            'password_confirmation' => 'MyOwnPass1',
        ])->assertOk();

        $this->assertSame('active', $user->fresh()->status);

        $this->postJson('/api/auth/login', ['email' => 'new.person@acme-trading.test', 'password' => 'MyOwnPass1'])
            ->assertOk();

        // The link works once.
        $this->getJson("/api/auth/invitation/{$token}")->assertNotFound();
        $this->postJson('/api/auth/invitation/accept', [
            'token' => $token, 'password' => 'Another123', 'password_confirmation' => 'Another123',
        ])->assertStatus(422)->assertJsonValidationErrors('token');
    }

    public function test_an_expired_link_is_refused(): void
    {
        Notification::fake();
        $t = $this->makeTenant('Acme Trading');
        $token = $this->tokenFrom($this->invite($t)->json('invitation_url'));

        $this->travel(8)->days();

        $this->getJson("/api/auth/invitation/{$token}")->assertNotFound();
    }

    public function test_the_admin_gets_the_link_when_the_email_cannot_be_sent(): void
    {
        $t = $this->makeTenant('Acme Trading');
        config([
            'mail.default' => 'smtp',
            'mail.mailers.smtp.host' => '127.0.0.1',
            'mail.mailers.smtp.port' => 1,
            'mail.mailers.smtp.timeout' => 2,
        ]);

        $response = $this->invite($t)->assertCreated()->assertJsonPath('invitation_sent', false);

        $this->getJson('/api/auth/invitation/'.$this->tokenFrom($response->json('invitation_url')))->assertOk();
    }

    public function test_resending_issues_a_new_link_and_retires_the_old_one(): void
    {
        Notification::fake();
        $t = $this->makeTenant('Acme Trading');
        $first = $this->tokenFrom($this->invite($t)->json('invitation_url'));
        $user = User::where('email', 'new.person@acme-trading.test')->firstOrFail();

        $second = $this->tokenFrom(
            $this->actingAs($t['admin'], 'sanctum')
                ->postJson("/api/employees/{$user->id}/resend-invitation")
                ->assertOk()->json('invitation_url')
        );

        $this->getJson("/api/auth/invitation/{$first}")->assertNotFound();
        $this->getJson("/api/auth/invitation/{$second}")->assertOk();
    }

    public function test_resending_to_someone_already_signing_in_keeps_their_password(): void
    {
        Notification::fake();
        $t = $this->makeTenant('Acme Trading');
        $t['employee']->forceFill(['last_login_at' => now()])->save();

        $this->actingAs($t['admin'], 'sanctum')
            ->postJson("/api/employees/{$t['employee']->id}/resend-invitation")
            ->assertOk();

        $this->assertSame('active', $t['employee']->fresh()->status);
        $this->postJson('/api/auth/login', ['email' => $t['employee']->email, 'password' => 'Password123!'])->assertOk();
    }

    public function test_a_removed_person_can_be_invited_again(): void
    {
        Notification::fake();
        $t = $this->makeTenant('Acme Trading');
        $email = $t['employee']->email;

        $this->actingAs($t['admin'], 'sanctum')->deleteJson("/api/employees/{$t['employee']->id}")->assertOk();

        $this->invite($t, $email)->assertCreated()->assertJsonPath('data.id', $t['employee']->id);
    }
}
