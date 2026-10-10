<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Sends one plain email with the live mail settings and prints exactly what
 * happened — the quickest way to see why sign-in or reset codes do not
 * arrive. Prints the settings in use (never the password).
 */
class MailTest extends Command
{
    protected $signature = 'vouchflow:mail-test {to : Address to send the test email to}';

    protected $description = 'Send a test email with the current mail settings and report the result';

    public function handle(): int
    {
        $mailer = config('mail.default');
        $settings = config("mail.mailers.{$mailer}", []);

        $this->table(['Setting', 'Value'], [
            ['MAIL_MAILER', $mailer],
            ['MAIL_HOST', $settings['host'] ?? '—'],
            ['MAIL_PORT', $settings['port'] ?? '—'],
            ['MAIL_SCHEME / encryption', $settings['scheme'] ?? $settings['encryption'] ?? '—'],
            ['MAIL_USERNAME', $settings['username'] ?? '—'],
            ['MAIL_PASSWORD', empty($settings['password']) ? '(empty)' : '(set)'],
            ['MAIL_FROM_ADDRESS', config('mail.from.address')],
            ['Reply-to', config('mail.reply_to.address') ?? '—'],
        ]);

        if (in_array($mailer, ['log', 'array'], true)) {
            $this->error("MAIL_MAILER is '{$mailer}': emails are written to the log, not sent. Set MAIL_MAILER=smtp and the MAIL_* settings in .env, then php artisan config:clear.");

            return self::FAILURE;
        }

        try {
            Mail::raw(
                "This is a test from VouchFlow. If you can read it, sign-in and password reset codes will arrive too.\n\nSent ".now()->toDayDateTimeString().'.',
                fn ($m) => $m->to($this->argument('to'))->subject('VouchFlow mail test'),
            );
        } catch (Throwable $e) {
            $this->error('Sending failed: '.get_class($e));
            $this->line($e->getMessage());

            return self::FAILURE;
        }

        $this->info('Sent. Check the inbox (and spam folder) of '.$this->argument('to').'.');

        return self::SUCCESS;
    }
}
