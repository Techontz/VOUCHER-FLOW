<?php

namespace App\Services\Sms;

/**
 * Sends a text message. The driver is chosen by `services.sms.driver`; only the
 * `log` driver ships today, and a provider plugs in by implementing this.
 */
interface SmsSender
{
    public function send(string $to, string $message): void;
}
