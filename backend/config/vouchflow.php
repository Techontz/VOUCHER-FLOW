<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Demo tenants
    |--------------------------------------------------------------------------
    |
    | Whether `php artisan db:seed` also builds the demo world. Off unless
    | asked for: three fictional companies appearing in a live tenant list is
    | not a recoverable kind of mistake.
    |
    | This lives in config rather than being read straight from the environment
    | in the seeder, because a production box normally runs `config:cache`, and
    | with the config cached `env()` no longer sees .env.
    |
    | DemoSeeder can always be run directly and deliberately:
    |   php artisan db:seed --class=DemoSeeder --force
    |
    */
    'seed_demo' => filter_var(env('SEED_DEMO', false), FILTER_VALIDATE_BOOLEAN),

    'trial_days' => (int) env('VOUCHFLOW_TRIAL_DAYS', 14),
    'max_upload_mb' => (int) env('VOUCHFLOW_MAX_UPLOAD_MB', 10),
    'payments_driver' => env('PAYMENTS_DRIVER', 'demo'),
    'frontend_url' => env('FRONTEND_URL', 'http://localhost:3000'),

    'locales' => ['en', 'sw'],
    'default_locale' => 'en',

    'allowed_upload_mimes' => [
        'application/pdf',
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/heic',
    ],
];
