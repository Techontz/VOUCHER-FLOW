<?php

namespace App\Http\Middleware;

use App\Models\Company;
use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Binds the request to exactly one tenant, immediately after authentication.
 *
 * Every tenant-owned model reads this through the global tenant scope, so no
 * controller has to remember to filter by company — and a controller that forgets
 * returns nothing rather than leaking.
 */
class ResolveTenant
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (! $user) {
            $this->tenant->clear();

            return $next($request);
        }

        if ($user->isSuperAdmin()) {
            // A super admin browses the platform unscoped, but may pin the request
            // to one company to inspect it — and is then held to that boundary.
            $companyId = $request->header('X-Company-Id') ?: $request->query('company_id');

            if ($companyId && $company = Company::find($companyId)) {
                $this->tenant->set($company);
            } else {
                $this->tenant->asPlatform();
            }

            return $next($request);
        }

        $company = $user->company;

        if (! $company) {
            // The company was deleted (or never existed). This session can do
            // nothing, so end it: a 401 sends the web and the app back to the
            // sign-in screen, where the account is then refused with a reason.
            $this->tenant->clear();
            $user->currentAccessToken()?->delete();

            return response()->json([
                'message' => 'This company account is no longer available. Contact support@vouchflow.co.tz.',
                'code' => 'company_unavailable',
            ], 401);
        }

        $this->tenant->set($company);

        return $next($request);
    }
}
