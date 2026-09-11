<?php

/*
 * Both clients authenticate with a Sanctum bearer token rather than a session
 * cookie, so credentialed requests are not needed and the origin list can stay
 * an explicit allowlist instead of a wildcard.
 *
 * The defaults cover local development for the Next.js app and the Flutter web
 * build. A deployment sets CORS_ALLOWED_ORIGINS to its own front-end origins.
 */
return [
    'paths' => ['api/*', 'storage/*', 'sanctum/csrf-cookie'],

    'allowed_methods' => ['*'],

    'allowed_origins' => array_filter(explode(',', (string) env(
        'CORS_ALLOWED_ORIGINS',
        'http://localhost:3000,http://127.0.0.1:3000,http://localhost:8091,http://127.0.0.1:8091',
    ))),

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => ['Content-Disposition'],

    'max_age' => 3600,

    'supports_credentials' => false,
];
