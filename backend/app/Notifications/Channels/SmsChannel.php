<?php

namespace App\Notifications\Channels;

use App\Services\Sms\SmsSender;
use Illuminate\Notifications\Notification;

/**
 * Delivers a notification's `toSms()` text to the notifiable's phone number
 * through whichever SMS driver is configured.
 */
class SmsChannel
{
    public function __construct(private readonly SmsSender $sms) {}

    public function send(object $notifiable, Notification $notification): void
    {
        $to = $notifiable->routeNotificationFor('sms', $notification) ?? $notifiable->phone ?? null;

        if (! $to || ! method_exists($notification, 'toSms')) {
            return;
        }

        $this->sms->send((string) $to, $notification->toSms($notifiable));
    }
}
