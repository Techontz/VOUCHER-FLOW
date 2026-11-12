<?php

namespace App\Console\Commands;

use App\Services\Erp\Documents\ExpiryAlerts;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

#[Signature('documents:expiry-alerts')]
#[Description('Notify owners and documents managers about documents that are about to expire')]
class SendDocumentExpiryAlerts extends Command
{
    public function handle(ExpiryAlerts $alerts): int
    {
        $sent = $alerts->run();
        $this->info("Sent {$sent} expiry alert(s).");

        return self::SUCCESS;
    }
}
