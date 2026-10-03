<?php

namespace App\Http\Middleware;

use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Holds a self-registered company at the door until the platform approves it.
 *
 * A pending company can manage its own account, finish its company profile,
 * read its notifications and choose and pay for a plan — everything the
 * "awaiting approval" screen needs — but nothing else: no people, no
 * vouchers, no workflows. Super admins are never held here.
 */
class EnsureCompanyApproved
{
    /**
     * What stays open while pending, as [methods, path patterns].
     * Paths are relative to the api prefix and matched with Request::is().
     *
     * @var list<array{0:list<string>,1:list<string>}>
     */
    private const ALLOWED = [
        // Account: me, logout, logout-all, change-password, sessions.
        [['*'], ['auth/*']],
        [['*'], ['profile', 'profile/*']],

        // The company's own profile and logo, written right after registering.
        [['GET', 'HEAD'], ['company', 'company/*']],
        [['PUT', 'PATCH'], ['company']],
        [['POST'], ['company/branding', 'company/logo']],
        [['DELETE'], ['company/logo']],

        // Choosing and paying for a plan while waiting.
        [['*'], ['billing/*']],

        // Including being told when the approval comes.
        [['*'], ['notifications', 'notifications/*']],
    ];

    public function __construct(private readonly TenantContext $tenant) {}

    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user()?->isSuperAdmin()) {
            return $next($request);
        }

        $company = $this->tenant->company();

        if (! $company || ! $company->isPending() || $this->isAllowed($request)) {
            return $next($request);
        }

        return response()->json([
            'message' => 'Your company is waiting for approval. You can choose a plan and pay while you wait.',
            'code' => 'company_pending',
            'status' => $company->status,
        ], 403);
    }

    private function isAllowed(Request $request): bool
    {
        $method = $request->getMethod();

        foreach (self::ALLOWED as [$methods, $paths]) {
            if ($methods !== ['*'] && ! in_array($method, $methods, true)) {
                continue;
            }

            foreach ($paths as $path) {
                if ($request->is('api/'.$path)) {
                    return true;
                }
            }
        }

        return false;
    }
}
