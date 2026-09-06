<?php

namespace App\Http\Middleware;

use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Blocks write operations for a tenant whose trial has lapsed or whose account is
 * suspended. Reading, billing and profile routes stay open so the company can see
 * its data and settle up.
 */
class EnsureSubscriptionActive
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function handle(Request $request, Closure $next): Response
    {
        $company = $this->tenant->company();

        if (! $company || $request->isMethod('GET')) {
            return $next($request);
        }

        if ($company->isUsable()) {
            return $next($request);
        }

        return response()->json([
            'message' => $company->status === 'suspended'
                ? 'This company account has been suspended. Contact your administrator.'
                : 'Your subscription has expired. Renew it to continue creating and approving vouchers.',
            'code' => 'subscription_inactive',
            'status' => $company->status,
        ], 402);
    }
}
