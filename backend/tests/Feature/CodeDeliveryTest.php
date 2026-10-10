<?php

namespace Tests\Feature;

use App\Models\OtpCode;
use App\Models\User;
use App\Notifications\OneTimeCodeNotification;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Reset and verification codes travel by email. When the mail server cannot
 * be reached the person must be told, not left waiting for an email that
 * was never sent.
 */
class CodeDeliveryTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function deliveredCode(User $user, string $purpose): string
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

    private function unreachableMailServer(): void
    {
        config([
            'mail.default' => 'smtp',
            'mail.mailers.smtp.host' => '127.0.0.1',
            'mail.mailers.smtp.port' => 1,
            'mail.mailers.smtp.timeout' => 2,
        ]);
    }

    public function test_a_reset_code_that_cannot_be_sent_is_reported(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $this->unreachableMailServer();

        $this->postJson('/api/auth/forgot-password', ['email' => $t['employee']->email])
            ->assertStatus(503)
            ->assertJsonPath('code', 'delivery_failed');

        // No code that nobody received is left usable.
        $this->assertSame(0, OtpCode::whereNull('consumed_at')->where('user_id', $t['employee']->id)->count());
    }

    public function test_an_unknown_address_still_gets_the_same_answer_when_mail_is_down(): void
    {
        $this->makeTenant('Acme Trading');
        $this->unreachableMailServer();

        $this->postJson('/api/auth/forgot-password', ['email' => 'nobody@nowhere.test'])->assertOk();
    }

    public function test_the_reset_accepts_a_differently_typed_address_and_a_spaced_code(): void
    {
        $t = $this->makeTenant('Acme Trading');
        Notification::fake();

        $this->postJson('/api/auth/forgot-password', ['email' => '  '.strtoupper($t['employee']->email).' '])->assertOk();
        $code = $this->deliveredCode($t['employee'], 'password_reset');

        $this->postJson('/api/auth/reset-password', [
            'email' => strtoupper($t['employee']->email),
            'code' => substr($code, 0, 3).' '.substr($code, 3),
            'password' => 'BrandNew123!',
            'password_confirmation' => 'BrandNew123!',
        ])->assertOk();
    }

    public function test_the_email_shows_the_code_on_its_own_line(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $html = (string) (new OneTimeCodeNotification('482913', 'password_reset'))
            ->toMail($t['employee'])->render();

        $this->assertStringContainsString('482913</p>', $html);
        $this->assertStringContainsString('password reset code', $html);
    }

    public function test_the_mail_test_command_flags_a_log_only_mailer(): void
    {
        config(['mail.default' => 'log']);

        $this->artisan('vouchflow:mail-test', ['to' => 'someone@example.com'])
            ->expectsOutputToContain("MAIL_MAILER is 'log'")
            ->assertFailed();
    }
}
