<?php

return [
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
