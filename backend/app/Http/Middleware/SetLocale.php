<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * English is the default; Swahili is chosen per request (header or query) or per
 * user preference.
 */
class SetLocale
{
    public function handle(Request $request, Closure $next): Response
    {
        $supported = config('vouchflow.locales', ['en']);

        $locale = $request->header('X-Locale')
            ?: $request->query('locale')
            ?: $request->user()?->locale
            ?: config('vouchflow.default_locale', 'en');

        app()->setLocale(in_array($locale, $supported, true) ? $locale : 'en');

        return $next($request);
    }
}
