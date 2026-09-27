<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\LoginChallenge;
use App\Models\OtpCode;
use App\Models\User;
use App\Notifications\Channels\SmsChannel;
use App\Notifications\OneTimeCodeNotification;
use Database\Seeders\PlanSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;
use Tests\TestSupport;

class TwoFactorLoginTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    protected function setUp(): void
    {
        parent::setUp();

        Notification::fake();
    }

    private function login(string $email, string $password = 'Password123!'): TestResponse
    {
        return $this->postJson('/api/auth/login', ['email' => $email, 'password' => $password, 'device_name' => 'test']);
    }

    /** The most recent sign-in code delivered to this user. */
    private function lastCodeFor(User $user, string $purpose = 'login'): string
    {
        $code = null;

        Notification::assertSentTo($user, OneTimeCodeNotification::class, function (OneTimeCodeNotification $n) use (&$code, $purpose) {
            if ($n->purpose === $purpose) {
                $code = $n->code;
            }

            return true;
        });

        $this->assertNotNull($code);

        return $code;
    }

    private function wrongCode(string $code): string
    {
        return $code === '111111' ? '222222' : '111111';
    }

    public function test_login_requires_verification_and_returns_no_token(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $response = $this->login($t['employee']->email)
            ->assertOk()
            ->assertJsonPath('requires_verification', true)
            ->assertJsonPath('sent_to', 'email')
            ->assertJsonPath('channels.0.channel', 'email')
            ->assertJsonPath('channels.0.destination', 'e•••@acme-trading.test')
            ->assertJsonCount(1, 'channels')
            ->assertJsonMissingPath('token');

        $this->assertNotEmpty($response->json('challenge'));
        $this->assertNull($t['employee']->fresh()->last_login_at);
        $this->assertSame(0, $t['employee']->tokens()->count());

        $code = $this->lastCodeFor($t['employee']);
        Notification::assertSentTo($t['employee'], OneTimeCodeNotification::class, fn ($n, array $channels) => $channels === ['mail']);

        $verified = $this->postJson('/api/auth/login/verify', [
            'challenge' => $response->json('challenge'),
            'code' => $code,
            'device_name' => 'test',
        ])->assertOk()->assertJsonStructure(['token', 'user', 'company']);

        $this->assertNotEmpty($verified->json('token'));
        $this->assertNotNull($t['employee']->fresh()->last_login_at);
        $this->assertTrue(AuditLog::where('action', 'auth.login')->where('actor_id', $t['employee']->id)->exists());

        // A challenge is single use.
        $this->postJson('/api/auth/login/verify', ['challenge' => $response->json('challenge'), 'code' => $code])
            ->assertStatus(422)
            ->assertJsonPath('reason', 'challenge_expired');
    }

    public function test_wrong_code_reports_remaining_attempts_and_locks_out(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $challenge = $this->login($t['employee']->email)->json('challenge');
        $code = $this->lastCodeFor($t['employee']);

        $this->postJson('/api/auth/login/verify', ['challenge' => $challenge, 'code' => $this->wrongCode($code)])
            ->assertStatus(422)
            ->assertJsonPath('reason', 'invalid_code')
            ->assertJsonPath('attempts_remaining', 4)
            ->assertJsonValidationErrors('code');

        foreach ([3, 2, 1] as $remaining) {
            $this->postJson('/api/auth/login/verify', ['challenge' => $challenge, 'code' => $this->wrongCode($code)])
                ->assertJsonPath('attempts_remaining', $remaining);
        }

        $this->postJson('/api/auth/login/verify', ['challenge' => $challenge, 'code' => $this->wrongCode($code)])
            ->assertStatus(422)
            ->assertJsonPath('reason', 'too_many_attempts');

        // The challenge is dead, even with the right code.
        $this->postJson('/api/auth/login/verify', ['challenge' => $challenge, 'code' => $code])
            ->assertStatus(422)
            ->assertJsonPath('reason', 'challenge_expired');

        $this->assertSame(0, $t['employee']->tokens()->count());
    }

    public function test_an_expired_code_is_refused_with_its_own_message(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $challenge = $this->login($t['employee']->email)->json('challenge');
        $code = $this->lastCodeFor($t['employee']);

        $this->travel(11)->minutes();

        $this->postJson('/api/auth/login/verify', ['challenge' => $challenge, 'code' => $code])
            ->assertStatus(422)
            ->assertJsonPath('reason', 'code_expired')
            ->assertJsonPath('message', 'That code has expired. Request a new one.');

        // A fresh code on the same challenge works.
        $this->postJson('/api/auth/login/send-code', ['challenge' => $challenge, 'channel' => 'email'])->assertOk();
        $fresh = $this->lastCodeFor($t['employee']);

        $this->postJson('/api/auth/login/verify', ['challenge' => $challenge, 'code' => $fresh])->assertOk();
    }

    public function test_an_expired_challenge_means_signing_in_again(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $challenge = $this->login($t['employee']->email)->json('challenge');
        $code = $this->lastCodeFor($t['employee']);

        $this->travel(16)->minutes();

        $this->postJson('/api/auth/login/verify', ['challenge' => $challenge, 'code' => $code])
            ->assertStatus(422)
            ->assertJsonPath('reason', 'challenge_expired');

        $this->postJson('/api/auth/login/send-code', ['challenge' => $challenge, 'channel' => 'email'])
            ->assertStatus(422)
            ->assertJsonPath('reason', 'challenge_expired');
    }

    public function test_resending_is_throttled_and_replaces_the_previous_code(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $challenge = $this->login($t['employee']->email)->json('challenge');
        $first = $this->lastCodeFor($t['employee']);

        $this->postJson('/api/auth/login/send-code', ['challenge' => $challenge, 'channel' => 'email'])
            ->assertStatus(429)
            ->assertJsonPath('reason', 'resend_cooldown')
            ->assertHeader('Retry-After');

        $this->travel(31)->seconds();

        $this->postJson('/api/auth/login/send-code', ['challenge' => $challenge, 'channel' => 'email'])
            ->assertOk()
            ->assertJsonPath('sent_to', 'email')
            ->assertJsonPath('resend_in', 30)
            ->assertJsonPath('sends_remaining', 3);

        Notification::assertSentToTimes($t['employee'], OneTimeCodeNotification::class, 2);
        $second = $this->lastCodeFor($t['employee']);

        if ($first !== $second) {
            $this->postJson('/api/auth/login/verify', ['challenge' => $challenge, 'code' => $first])
                ->assertStatus(422)
                ->assertJsonPath('reason', 'invalid_code');
        }

        // Sends are capped per challenge.
        for ($i = 0; $i < 3; $i++) {
            $this->travel(31)->seconds();
            $this->postJson('/api/auth/login/send-code', ['challenge' => $challenge, 'channel' => 'email'])->assertOk();
        }

        $this->travel(31)->seconds();
        $this->postJson('/api/auth/login/send-code', ['challenge' => $challenge, 'channel' => 'email'])
            ->assertStatus(429)
            ->assertJsonPath('reason', 'too_many_sends');
    }

    public function test_sms_is_offered_only_when_the_account_has_a_phone(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->postJson('/api/auth/login/send-code', [
            'challenge' => $this->login($t['employee']->email)->json('challenge'),
            'channel' => 'sms',
        ])->assertStatus(422)->assertJsonValidationErrors('channel');

        $t['ceo']->forceFill(['phone' => '+255712345418'])->save();

        $response = $this->login($t['ceo']->email)
            ->assertOk()
            ->assertJsonCount(2, 'channels')
            ->assertJsonPath('channels.1.channel', 'sms')
            ->assertJsonPath('channels.1.destination', '+255 7•• ••• 418')
            ->assertJsonPath('sent_to', null);

        // With a choice to make, nothing is sent until the person picks.
        Notification::assertNotSentTo($t['ceo'], OneTimeCodeNotification::class);

        $this->postJson('/api/auth/login/verify', ['challenge' => $response->json('challenge'), 'code' => '123456'])
            ->assertStatus(422)
            ->assertJsonPath('reason', 'no_code');

        $this->postJson('/api/auth/login/send-code', ['challenge' => $response->json('challenge'), 'channel' => 'sms'])
            ->assertOk()
            ->assertJsonPath('sent_to', 'sms')
            ->assertJsonPath('destination', '+255 7•• ••• 418');

        Notification::assertSentTo($t['ceo'], OneTimeCodeNotification::class, function ($n, array $channels) {
            return $n->channel === 'sms' && $channels === [SmsChannel::class];
        });

        $this->postJson('/api/auth/login/verify', [
            'challenge' => $response->json('challenge'),
            'code' => $this->lastCodeFor($t['ceo']),
        ])->assertOk()->assertJsonPath('user.id', $t['ceo']->id);
    }

    public function test_codes_never_appear_in_any_response(): void
    {
        $this->seed(PlanSeeder::class);

        $register = $this->postJson('/api/auth/register', [
            'company_name' => 'Northwind Traders',
            'business_email' => 'accounts@northwind.test',
            'name' => 'Amina Said',
            'email' => 'amina@northwind.test',
            'password' => 'Password123!',
            'password_confirmation' => 'Password123!',
        ])->assertCreated();

        $admin = User::where('email', 'amina@northwind.test')->firstOrFail();
        $admin->company->forceFill(['status' => 'active'])->save();
        $registrationCode = $this->lastCodeFor($admin, 'registration');
        $this->assertStringNotContainsString($registrationCode, $register->getContent());
        $this->assertNull($register->json('otp.code'));

        $login = $this->login('amina@northwind.test');
        $send = $this->travel(31)->seconds(fn () => $this->postJson('/api/auth/login/send-code', ['challenge' => $login->json('challenge'), 'channel' => 'email']));
        $resend = $this->postJson('/api/auth/otp/send', ['identifier' => 'amina@northwind.test', 'purpose' => 'registration']);
        $forgot = $this->postJson('/api/auth/forgot-password', ['email' => 'amina@northwind.test']);

        Notification::assertSentTo($admin, OneTimeCodeNotification::class, function (OneTimeCodeNotification $n) use ($login, $send, $resend, $forgot) {
            foreach ([$login, $send, $resend, $forgot] as $response) {
                $this->assertStringNotContainsString($n->code, $response->getContent());
            }

            return true;
        });

        $this->assertNull($forgot->json('otp.code'));
        $this->assertNull($resend->json('otp.code'));
    }

    public function test_a_user_suspended_after_the_password_step_is_stopped_at_verification(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $challenge = $this->login($t['employee']->email)->json('challenge');
        $code = $this->lastCodeFor($t['employee']);

        $t['employee']->forceFill(['status' => 'suspended'])->save();

        $this->postJson('/api/auth/login/verify', ['challenge' => $challenge, 'code' => $code])
            ->assertStatus(422)
            ->assertJsonPath('reason', 'account_unavailable');

        $this->assertSame(0, $t['employee']->tokens()->count());
    }

    public function test_one_users_challenge_cannot_carry_another_users_code(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $challengeA = $this->login($t['employee']->email)->json('challenge');
        $this->login($t['hod']->email);
        $codeB = $this->lastCodeFor($t['hod']);
        $codeA = $this->lastCodeFor($t['employee']);

        if ($codeA !== $codeB) {
            $this->postJson('/api/auth/login/verify', ['challenge' => $challengeA, 'code' => $codeB])
                ->assertStatus(422)
                ->assertJsonPath('reason', 'invalid_code');
        }

        $this->postJson('/api/auth/login/verify', ['challenge' => $challengeA, 'code' => $codeA])
            ->assertOk()
            ->assertJsonPath('user.id', $t['employee']->id);

        $this->postJson('/api/auth/login/verify', ['challenge' => 'not-a-real-challenge', 'code' => $codeB])
            ->assertStatus(422)
            ->assertJsonPath('reason', 'challenge_expired');
    }

    public function test_an_address_shared_by_two_companies_signs_in_the_right_account(): void
    {
        $alpha = $this->makeTenant('Alpha Ltd');
        $beta = $this->makeTenant('Beta Ltd');

        $alpha['employee']->forceFill(['email' => 'shared@example.test'])->save();
        $beta['employee']->forceFill(['email' => 'shared@example.test', 'password' => 'BetaPassword1!'])->save();

        $challenge = $this->login('shared@example.test', 'BetaPassword1!')->assertOk()->json('challenge');

        Notification::assertNotSentTo($alpha['employee'], OneTimeCodeNotification::class);

        $this->postJson('/api/auth/login/verify', ['challenge' => $challenge, 'code' => $this->lastCodeFor($beta['employee'])])
            ->assertOk()
            ->assertJsonPath('user.id', $beta['employee']->id);

        $this->assertSame($beta['employee']->id, LoginChallenge::sole()->user_id);
    }

    public function test_the_kill_switch_restores_single_step_sign_in(): void
    {
        config(['vouchflow.two_factor' => false]);
        $t = $this->makeTenant('Acme Trading');

        $this->login($t['employee']->email)
            ->assertOk()
            ->assertJsonStructure(['token', 'user', 'company'])
            ->assertJsonMissingPath('requires_verification');

        Notification::assertNothingSent();
    }

    public function test_the_otp_endpoints_can_no_longer_sign_anyone_in(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->postJson('/api/auth/otp/send', ['identifier' => $t['employee']->email, 'purpose' => 'login'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('purpose');

        $this->postJson('/api/auth/otp/verify', ['identifier' => $t['employee']->email, 'code' => '123456', 'purpose' => 'login'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('purpose');

        // A password-reset code is not a way in either.
        $this->postJson('/api/auth/forgot-password', ['email' => $t['employee']->email])->assertOk();
        $code = $this->lastCodeFor($t['employee'], 'password_reset');

        $this->postJson('/api/auth/otp/verify', ['identifier' => $t['employee']->email, 'code' => $code, 'purpose' => 'password_reset'])
            ->assertStatus(422);

        $this->assertSame(0, $t['employee']->tokens()->count());
    }

    public function test_unknown_identifiers_get_no_codes_and_reissuing_retires_the_old_code(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->postJson('/api/auth/otp/send', ['identifier' => 'nobody@nowhere.test', 'purpose' => 'password_reset'])
            ->assertOk()
            ->assertJsonPath('otp.identifier', 'nobody@nowhere.test');
        $this->assertSame(0, OtpCode::where('identifier', 'nobody@nowhere.test')->count());

        $this->postJson('/api/auth/forgot-password', ['email' => $t['employee']->email])->assertOk();
        $old = $this->lastCodeFor($t['employee'], 'password_reset');
        Notification::fake();
        $this->postJson('/api/auth/forgot-password', ['email' => $t['employee']->email])->assertOk();
        $new = $this->lastCodeFor($t['employee'], 'password_reset');

        $this->assertSame(1, OtpCode::where('user_id', $t['employee']->id)->whereNull('consumed_at')->count());

        $payload = ['email' => $t['employee']->email, 'password' => 'BrandNew123!', 'password_confirmation' => 'BrandNew123!'];

        if ($old !== $new) {
            $this->postJson('/api/auth/reset-password', [...$payload, 'code' => $old])->assertStatus(422);
        }

        $this->postJson('/api/auth/reset-password', [...$payload, 'code' => $new])->assertOk();
    }

    public function test_reset_codes_stop_working_after_repeated_wrong_guesses(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->postJson('/api/auth/forgot-password', ['email' => $t['employee']->email])->assertOk();
        $code = $this->lastCodeFor($t['employee'], 'password_reset');
        $payload = ['email' => $t['employee']->email, 'password' => 'BrandNew123!', 'password_confirmation' => 'BrandNew123!'];

        for ($i = 0; $i < 6; $i++) {
            // Stay under the per-minute route throttle, so each refusal is the code's.
            if ($i === 4) {
                $this->travel(61)->seconds();
            }

            $this->postJson('/api/auth/reset-password', [...$payload, 'code' => $this->wrongCode($code)])->assertStatus(422);
        }

        $this->postJson('/api/auth/reset-password', [...$payload, 'code' => $code])->assertStatus(422);
    }
}
