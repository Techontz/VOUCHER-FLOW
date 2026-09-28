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
