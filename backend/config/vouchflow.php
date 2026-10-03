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
    /*
    | 24-hour voucher reminders (in-app, plus email when mail is configured).
    */
    'reminders' => [
        'enabled' => filter_var(env('VOUCHFLOW_REMINDERS', true), FILTER_VALIDATE_BOOLEAN),
        'email' => filter_var(env('VOUCHFLOW_REMINDER_EMAILS', true), FILTER_VALIDATE_BOOLEAN),
    ],

    'seed_demo' => filter_var(env('SEED_DEMO', false), FILTER_VALIDATE_BOOLEAN),

    /*
    |--------------------------------------------------------------------------
    | Platform operator
    |--------------------------------------------------------------------------
    |
    | The account DatabaseSeeder creates, read from config for the same reason
    | as seed_demo. There is no fallback password outside local work: a
    | production seed without SUPER_ADMIN_PASSWORD skips the account instead of
    | creating one with a published password.
    |
    */
    'super_admin' => [
        'email' => env('SUPER_ADMIN_EMAIL', 'super@vouchflow.test'),
        'password' => env('SUPER_ADMIN_PASSWORD') ?: null,
    ],

    /*
    |--------------------------------------------------------------------------
    | Two-step sign-in
    |--------------------------------------------------------------------------
    |
    | Every sign-in asks for a one-time code, sent by e-mail (or SMS when the
    | account has a phone number), after the password. This is the kill-switch
    | for when mail delivery is down: with it off, a correct password returns a
    | token straight away, exactly as before two-step sign-in existed.
    |
    */
    'two_factor' => filter_var(env('VOUCHFLOW_TWO_FACTOR', true), FILTER_VALIDATE_BOOLEAN),

    // Addresses on these reserved domains (RFC 2606 — demo and test accounts)
    // can never receive a code, so they sign in with the password alone. A
    // domain matches itself and any subdomain; set the variable to an empty
    // string to require a code from everyone.
    'two_factor_skip_domains' => array_values(array_filter(array_map('trim', explode(',', (string) env(
        'VOUCHFLOW_TWO_FACTOR_SKIP_DOMAINS',
        'test,example,invalid,localhost,example.com,example.net,example.org',
    ))))),

    /*
    |--------------------------------------------------------------------------
    | E-mail check after self-registration
    |--------------------------------------------------------------------------
    |
    | Whether a new company's administrator is asked for a one-time code sent
    | to their address before carrying on. `auto` (the default) asks only when
    | a real mail transport is configured — with MAIL_MAILER=log or array the
    | code could never arrive, so asking for it would strand the person.
    | `true` or `false` force it either way.
    |
    | Resolved by AuthController::registrationEmailVerification().
    |
    */
    'registration_email_verification' => env('VOUCHFLOW_REGISTRATION_EMAIL_VERIFY', 'auto'),

    // Changes of voucher design a company may make itself after registration.
    // The platform's super admin is never bound by it.
    'voucher_template_self_changes' => (int) env('VOUCHFLOW_TEMPLATE_SELF_CHANGES', 1),

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
