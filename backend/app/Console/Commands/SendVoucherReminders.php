<?php

namespace App\Console\Commands;

use App\Services\VoucherReminders;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

#[Signature('vouchers:remind')]
#[Description('Remind whoever is holding a voucher once it has waited 24 hours')]
class SendVoucherReminders extends Command
{
    public function handle(VoucherReminders $reminders): int
    {
        if (! config('vouchflow.reminders.enabled', true)) {
            $this->info('Voucher reminders are switched off.');

            return self::SUCCESS;
        }

        $sent = $reminders->run();
        $this->info("Sent {$sent} reminder(s).");

        return self::SUCCESS;
    }
}
