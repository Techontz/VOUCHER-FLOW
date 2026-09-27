<?php

namespace App\Notifications;

use App\Notifications\Channels\SmsChannel;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * A one-time code for signing in, confirming a new account or resetting a
 * password. Sent synchronously: the person is waiting for it on screen.
 */
class OneTimeCodeNotification extends Notification
{
    public const PURPOSE_LOGIN = 'login';

    public const PURPOSE_REGISTRATION = 'registration';

    public const PURPOSE_PASSWORD_RESET = 'password_reset';

    public function __construct(
        public readonly string $code,
        public readonly string $purpose,
        public readonly string $channel = 'email',
        public readonly int $minutes = 10,
    ) {}

    /**
     * @return array<int, string>
     */
    public function via(object $notifiable): array
    {
        return [$this->channel === 'sms' ? SmsChannel::class : 'mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $swahili = ($notifiable->locale ?? null) === 'sw';

        return (new MailMessage)
            ->subject($this->subject($swahili))
            ->greeting($swahili ? 'Habari,' : 'Hello,')
            ->line($this->sentence($swahili))
            ->line($this->warning($swahili))
            ->salutation($swahili ? 'Timu ya VouchFlow' : 'The VouchFlow team');
    }

    public function toSms(object $notifiable): string
    {
        $swahili = ($notifiable->locale ?? null) === 'sw';

        return $this->sentence($swahili).' '.$this->warning($swahili);
    }

    private function subject(bool $swahili): string
    {
        return match ($this->purpose) {
            self::PURPOSE_LOGIN => $swahili ? 'Namba yako ya kuingia VouchFlow' : 'Your VouchFlow sign-in code',
            self::PURPOSE_PASSWORD_RESET => $swahili ? 'Namba yako ya kubadilisha nenosiri VouchFlow' : 'Your VouchFlow password reset code',
            default => $swahili ? 'Namba yako ya uthibitisho VouchFlow' : 'Your VouchFlow verification code',
        };
    }

    private function sentence(bool $swahili): string
    {
        $what = match ($this->purpose) {
            self::PURPOSE_LOGIN => $swahili ? 'ya kuingia' : 'sign-in',
            self::PURPOSE_PASSWORD_RESET => $swahili ? 'ya kubadilisha nenosiri' : 'password reset',
            default => $swahili ? 'ya uthibitisho' : 'verification',
        };

        return $swahili
            ? "Namba yako {$what} ya VouchFlow ni {$this->code}. Itaisha muda baada ya dakika {$this->minutes}."
            : "Your VouchFlow {$what} code is {$this->code}. It expires in {$this->minutes} minutes.";
    }

    private function warning(bool $swahili): string
    {
        return match ($this->purpose) {
            self::PURPOSE_LOGIN => $swahili
                ? 'Kama hukujaribu kuingia, badilisha nenosiri lako.'
                : "If you didn't try to sign in, change your password.",
            self::PURPOSE_PASSWORD_RESET => $swahili
                ? 'Kama hukuomba kubadilisha nenosiri, puuza ujumbe huu.'
                : "If you didn't ask to reset your password, you can ignore this message.",
            default => $swahili
                ? 'Kama hukufungua akaunti ya VouchFlow, puuza ujumbe huu.'
                : "If you didn't create a VouchFlow account, you can ignore this message.",
        };
    }
}
