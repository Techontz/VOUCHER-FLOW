<?php

namespace App\Http\Middleware;

use App\Support\Erp\Permissions;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/** `permission:inventory.post`, the caller's role must carry that permission. */
class EnsurePermission
{
    public function __construct(private readonly Permissions $permissions) {}

    public function handle(Request $request, Closure $next, string $permission): Response
    {
        $user = $request->user();

        abort_unless(
            $user && $this->permissions->allows($user, $permission),
            403,
            'Your role does not allow this. Ask your administrator for the '.(Permissions::catalogue()[$permission]['label'] ?? $permission).' permission.',
        );

        return $next($request);
    }
}
