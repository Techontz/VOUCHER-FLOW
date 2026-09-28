<?php

namespace App\Services;

use App\Models\LoginChallenge;
use App\Models\User;
use App\Notifications\OneTimeCodeNotification;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Throwable;

/**
 * The second step of signing in: after a correct password the person receives
 * a one-time code by e-mail or SMS and exchanges it for a token.
 *
 * The client holds only an opaque challenge id. The challenge is tied to the
 * user id it was opened for, so an address shared by two companies never
 * resolves to the wrong account on the way back.
 */
class TwoFactorLogin
{
    public const CODE_MINUTES = 10;

    public const CHALLENGE_MINUTES = 15;

    public const MAX_ATTEMPTS = 5;

    public const MAX_SENDS = 5;

    public const RESEND_SECONDS = 30;

    public function enabled(): bool
    {
        return (bool) config('vouchflow.two_factor', true);
    }

    /**
     * Whether this person must enter a code. Accounts on reserved demo/test
     * domains cannot receive one, so they are let through on the password.
     */
    public function requiredFor(User $user): bool
    {
        if (! $this->enabled()) {
            return false;
        }

        $domain = mb_strtolower((string) substr(strrchr((string) $user->email, '@') ?: '', 1));

        foreach ((array) config('vouchflow.two_factor_skip_domains', []) as $skip) {
            $skip = mb_strtolower(ltrim($skip, '.'));

            if ($skip !== '' && ($domain === $skip || str_ends_with($domain, '.'.$skip))) {
                return false;
            }
        }

        return true;
    }

    /**
     * Opens a challenge for a user whose password has just been accepted.
     *
     * @return array{requires_verification: true, challenge: string, channels: list<array{channel: string, destination: string}>, sent_to: ?string, expires_in: int, code_expires_in: ?int, resend_in: ?int}
     */
    public function start(User $user, ?string $ip): array
    {
        $token = Str::random(64);

        // A fresh password sign-in supersedes any challenge still open.
        LoginChallenge::where('user_id', $user->id)->whereNull('consumed_at')->update(['consumed_at' => now()]);

        $challenge = LoginChallenge::create([
            'user_id' => $user->id,
            'token_hash' => hash('sha256', $token),
            'ip' => $ip,
            'expires_at' => now()->addMinutes(self::CHALLENGE_MINUTES),
        ]);

        $channels = $this->channels($user);
        $sentTo = null;

        if (count($channels) === 1) {
            $this->send($challenge, $channels[0]['channel']);
            $sentTo = $channels[0]['channel'];
        }

        return [
            'requires_verification' => true,
            'challenge' => $token,
            'channels' => $channels,
            'sent_to' => $sentTo,
            'expires_in' => self::CHALLENGE_MINUTES * 60,
            'code_expires_in' => $sentTo ? self::CODE_MINUTES * 60 : null,
            'resend_in' => $sentTo ? self::RESEND_SECONDS : null,
        ];
    }

    /**
     * The ways a code can reach this person, with the destination masked.
     *
     * @return list<array{channel: string, destination: string}>
     */
    public function channels(User $user): array
    {
        $channels = [['channel' => 'email', 'destination' => self::maskEmail((string) $user->email)]];

        if (filled($user->phone)) {
            $channels[] = ['channel' => 'sms', 'destination' => self::maskPhone((string) $user->phone)];
        }

        return $channels;
    }

    /**
     * Issues a fresh code on the chosen channel. Any earlier code for the
     * challenge stops working.
     *
     * @return array{sent_to: string, destination: string, code_expires_in: int, resend_in: int, sends_remaining: int}
     */
    public function send(LoginChallenge $challenge, string $channel): array
    {
        $user = $challenge->user;

        $destination = collect($this->channels($user))->firstWhere('channel', $channel);

        if (! $destination) {
            throw ValidationException::withMessages(['channel' => ['That delivery method is not available for this account.']]);
        }

        if ($challenge->code_sent_at && $challenge->code_sent_at->diffInSeconds(now()) < self::RESEND_SECONDS) {
            $retryAfter = max(1, self::RESEND_SECONDS - (int) $challenge->code_sent_at->diffInSeconds(now()));

            $this->fail(429, 'resend_cooldown', "Please wait {$retryAfter} seconds before requesting another code.", 'code', [
                'retry_after' => $retryAfter,
            ]);
        }

        if ($challenge->sends >= self::MAX_SENDS) {
            $this->fail(429, 'too_many_sends', 'You have requested too many codes. Sign in again to continue.', 'code');
        }

        $code = (string) random_int(100000, 999999);

        try {
            $user->notify(new OneTimeCodeNotification($code, OneTimeCodeNotification::PURPOSE_LOGIN, $channel, self::CODE_MINUTES));
        } catch (Throwable $e) {
            report($e);

            $this->fail(503, 'delivery_failed', 'We could not send your code right now. Please try again shortly.', 'code');
        }

        $challenge->forceFill([
            'channel' => $channel,
            'code_hash' => Hash::make($code),
            'code_sent_at' => now(),
            'code_expires_at' => now()->addMinutes(self::CODE_MINUTES),
            'sends' => $challenge->sends + 1,
        ])->save();

        return [
            'sent_to' => $channel,
            'destination' => $destination['destination'],
            'code_expires_in' => self::CODE_MINUTES * 60,
            'resend_in' => self::RESEND_SECONDS,
            'sends_remaining' => self::MAX_SENDS - $challenge->sends,
        ];
    }

    /** Finds a challenge the client may still act on, or stops the request. */
    public function open(string $token): LoginChallenge
    {
        $challenge = LoginChallenge::findByToken($token);

        if (! $challenge || ! $challenge->isOpen() || ! $challenge->user) {
            $this->fail(422, 'challenge_expired', 'Your sign-in session has expired. Sign in again to continue.', 'code');
        }

        return $challenge;
    }

    /**
     * Checks a code. Returns the user on success and closes the challenge;
     * every failure is a 422 whose `reason` tells the client what to do next.
     */
    public function verify(LoginChallenge $challenge, string $code): User
    {
        if ($challenge->attempts >= self::MAX_ATTEMPTS) {
            $this->close($challenge);
            $this->fail(422, 'too_many_attempts', 'Too many incorrect codes. Sign in again to get a new code.', 'code');
        }

        if (! $challenge->code_hash) {
            $this->fail(422, 'no_code', 'Choose where to send your code first.', 'code');
        }

        if ($challenge->code_expires_at->isPast()) {
            $this->fail(422, 'code_expired', 'That code has expired. Request a new one.', 'code');
        }

        $challenge->increment('attempts');

        if (! Hash::check($code, $challenge->code_hash)) {
            $remaining = self::MAX_ATTEMPTS - $challenge->attempts;

            if ($remaining <= 0) {
                $this->close($challenge);
                $this->fail(422, 'too_many_attempts', 'Too many incorrect codes. Sign in again to get a new code.', 'code');
            }

            $this->fail(422, 'invalid_code', $remaining === 1
                ? 'That code is not correct. You have 1 attempt left.'
                : "That code is not correct. You have {$remaining} attempts left.", 'code', [
                    'attempts_remaining' => $remaining,
                ]);
        }

        // Closing is conditional so two simultaneous correct submissions cannot
        // both turn into tokens.
        $closed = LoginChallenge::whereKey($challenge->id)->whereNull('consumed_at')->update(['consumed_at' => now()]);

        if ($closed === 0) {
            $this->fail(422, 'challenge_expired', 'Your sign-in session has expired. Sign in again to continue.', 'code');
        }

        return $challenge->user()->with('company')->firstOrFail();
    }

    public function close(LoginChallenge $challenge): void
    {
        $challenge->forceFill(['consumed_at' => now()])->save();
    }

    /**
     * Stops the request with the JSON shape the clients read.
     *
     * @param  array<string, mixed>  $extra
     */
    public function fail(int $status, string $reason, string $message, string $field, array $extra = []): never
    {
        throw new HttpResponseException(response()->json([
            'message' => $message,
            'reason' => $reason,
            'errors' => [$field => [$message]],
            ...$extra,
        ], $status, isset($extra['retry_after']) ? ['Retry-After' => (string) $extra['retry_after']] : []));
    }

    public static function maskEmail(string $email): string
    {
        [$local, $domain] = array_pad(explode('@', $email, 2), 2, '');

        return mb_substr($local, 0, 1).'•••@'.$domain;
    }

    public static function maskPhone(string $phone): string
    {
        $digits = preg_replace('/\D/', '', $phone);
        $last = substr($digits, -3);

        if (str_starts_with(trim($phone), '+') && strlen($digits) >= 10) {
            return '+'.substr($digits, 0, 3).' '.substr($digits, 3, 1).'•• ••• '.$last;
        }

        return substr($digits, 0, 1).'••• ••• '.$last;
    }
}
