<?php

namespace App\Http\Middleware;

use App\Support\Erp\BusinessConfig;
use App\Support\Erp\BusinessTemplates;
use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Refuses a module the caller's company has not switched on, or that its
 * subscription does not include, with a message
 * that says so, rather than an empty list that looks like missing data.
 */
class EnsureModuleEnabled
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function handle(Request $request, Closure $next, string $module): Response
    {
        $company = $this->tenant->company();

        $config = $company ? BusinessConfig::of($company) : null;

        if (! $config || ! $config->hasModule($module)) {
            $label = BusinessTemplates::modules()[$module]['label'] ?? $module;

            // An app the subscription does not include cannot be fixed in
            // Business setup, so the message says where it can be.
            $message = $config && ! $config->isLicensed($module)
                ? "{$label} is not in this company's subscription. Ask VouchFlow to add it to your plan."
                : "{$label} is not switched on for this company. An administrator can enable it under Business setup.";

            return response()->json([
                'message' => $message,
                'code' => 'module_disabled',
                'module' => $module,
            ], 403);
        }

        return $next($request);
    }
}
