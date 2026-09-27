<?php

namespace App\Notifications;

use App\Models\Voucher;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * The daily reminder email: one message per person listing every voucher that
 * has waited on them for 24 hours or more. Each line matches the in-app
 * reminder for that voucher and links straight to it.
 */
class VoucherReminderNotification extends Notification
{
    /**
     * @param  array<int, array{title: string, body: string, voucher: Voucher}>  $items
     */
    public function __construct(
        public readonly array $items,
        public readonly bool $swahili = false,
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
        $count = count($this->items);
        $base = rtrim((string) config('vouchflow.frontend_url', config('app.url')), '/');

        $subject = $count === 1
            ? $this->items[0]['title']
            : ($this->swahili ? "Kumbusho: vocha {$count} zinakusubiri" : "Reminder: {$count} vouchers are waiting for you");

        $mail = (new MailMessage)
            ->subject($subject)
            ->greeting($this->swahili ? 'Habari,' : 'Hello,')
            ->line($this->swahili
                ? 'Vocha zifuatazo zimekusubiri kwa saa 24 au zaidi:'
                : 'The following vouchers have been waiting on you for 24 hours or more:');

        foreach ($this->items as $item) {
            $v = $item['voucher'];
            $mail->line("**{$v->number}** — {$v->purpose} ({$v->currency} ".number_format((float) $v->amount).'). '.$item['body']." {$base}/vouchers/{$v->id}");
        }

        return $mail
            ->action($this->swahili ? 'Fungua VouchFlow' : 'Open VouchFlow', $base.'/dashboard')
            ->salutation($this->swahili ? 'Timu ya VouchFlow' : 'The VouchFlow team');
    }
}
