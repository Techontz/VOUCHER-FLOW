<?php

namespace App\Services\Sms;

use Illuminate\Support\Facades\Log;

/**
 * Writes outgoing text messages to a log channel instead of a provider, the way
 * the `log` mailer does for e-mail. For local work and until a provider is set.
 */
class LogSmsSender implements SmsSender
{
    public function __construct(private readonly ?string $channel = null) {}

    public function send(string $to, string $message): void
    {
        Log::channel($this->channel)->info("SMS to {$to}: {$message}");
    }
}
