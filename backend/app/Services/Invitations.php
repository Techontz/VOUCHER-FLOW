<?php

namespace App\Services;

use App\Models\User;
use App\Notifications\InvitationNotification;
use Illuminate\Support\Str;

/**
 * The link a newly added person follows to choose their own password.
 *
 * Only a hash of the token is stored, so a copy of the database cannot be used
 * to take over an account that has not been claimed yet. The administrator is
 * handed the link as well: when mail does not leave the server they can still
 * pass it on another way, and nobody is left without a way in.
 */
class Invitations
{
    public const DAYS = 7;

    /**
     * Issues a fresh link (earlier ones stop working) and emails it.
     *
     * @return array{invitation_url: string, invitation_sent: bool}
     */
    public function issue(User $user, ?User $by = null): array
    {
        $token = Str::random(48);

        $user->forceFill([
            'invitation_token' => self::hash($token),
            'invited_at' => now(),
        ])->save();

        $url = rtrim((string) config('vouchflow.frontend_url', config('app.url')), '/').'/invite?token='.$token;

        try {
            $user->notify(new InvitationNotification(
                $url,
                (string) ($user->company?->name ?? 'VouchFlow'),
                $by?->name,
                self::DAYS,
            ));
            $sent = true;
        } catch (\Throwable $e) {
            // The account and the link stand; the administrator is told the
            // email did not go and is shown the link to share instead.
            report($e);
            $sent = false;
        }

        return ['invitation_url' => $url, 'invitation_sent' => $sent];
    }

    /** The unclaimed, unexpired account a link belongs to, if any. */
    public function find(string $token): ?User
    {
        if (strlen($token) < 20) {
            return null;
        }

        $user = User::with('company')->where('invitation_token', self::hash($token))->first();

        // A deleted company is soft-deleted, so `company` comes back empty.
        if (! $user || $user->status === 'suspended' || ! $user->company || ! $user->invited_at
            || $user->invited_at->lt(now()->subDays(self::DAYS))) {
            return null;
        }

        return $user;
    }

    public static function hash(string $token): string
    {
        return hash('sha256', $token);
    }
}
