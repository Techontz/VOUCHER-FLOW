<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Reminds whoever is holding a voucher once it has waited 24 hours; each
// person hears about a given voucher at most once a day. Needs the system
// cron entry: * * * * * php artisan schedule:run
Schedule::command('vouchers:remind')->hourly()->withoutOverlapping();

// Licences, insurance certificates and other documents with an expiry date:
// their owner and the documents managers hear 30, 14, 7 and 1 days ahead.
Schedule::command('documents:expiry-alerts')->dailyAt('07:00')->withoutOverlapping();
