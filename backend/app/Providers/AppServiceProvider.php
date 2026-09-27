<?php

namespace App\Providers;

use App\Services\Sms\LogSmsSender;
use App\Services\Sms\SmsSender;
use App\Support\TenantContext;
use Illuminate\Support\ServiceProvider;
use InvalidArgumentException;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // One tenant per request. The global tenant scope reads this instance,
        // so it must be a singleton for isolation to hold.
        $this->app->singleton(TenantContext::class);

        $this->app->singleton(SmsSender::class, fn () => match (config('services.sms.driver', 'log')) {
            'log' => new LogSmsSender(config('services.sms.log_channel')),
            default => throw new InvalidArgumentException('Unsupported SMS driver ['.config('services.sms.driver').'].'),
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
