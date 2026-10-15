<?php

namespace App\Notifications;

use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Asks a newly added person to choose their password. The link carries a
 * one-time token; nothing else about the account is in the message. Sent
 * synchronously so the administrator learns at once if it could not go.
 */
class InvitationNotification extends Notification
{
    public function __construct(
        public readonly string $url,
        public readonly string $companyName,
        public readonly ?string $invitedBy,
        public readonly int $days,
    ) {}

    /**
     * @return array<int, string>
     */
    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $swahili = ($notifiable->locale ?? null) === 'sw';
        $who = $this->invitedBy ?: ($swahili ? 'Msimamizi wako' : 'Your administrator');

        return (new MailMessage)
            ->subject($swahili
                ? "Umealikwa kujiunga na {$this->companyName} kwenye VouchFlow"
                : "You're invited to join {$this->companyName} on VouchFlow")
            ->greeting($swahili ? "Habari {$notifiable->name}," : "Hello {$notifiable->name},")
            ->line($swahili
                ? "{$who} amekuongeza kwenye {$this->companyName} kwenye VouchFlow."
                : "{$who} has added you to {$this->companyName} on VouchFlow.")
            ->line($swahili
                ? 'Weka nenosiri lako ili uanze kutumia akaunti yako.'
                : 'Set your password to start using your account.')
            ->action($swahili ? 'Weka nenosiri' : 'Set your password', $this->url)
            ->line($swahili
                ? "Kiungo hiki kinafanya kazi kwa siku {$this->days} na mara moja tu. Ingia kwa barua pepe hii: {$notifiable->email}"
                : "This link works once and for {$this->days} days. You will sign in with this address: {$notifiable->email}")
            ->salutation($swahili ? 'Timu ya VouchFlow' : 'The VouchFlow team');
    }
}
