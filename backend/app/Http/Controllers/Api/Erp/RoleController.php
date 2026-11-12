<?php

namespace App\Http\Controllers\Api\Erp;

use App\Http\Controllers\Controller;
use App\Models\Erp\CompanyRole;
use App\Models\User;
use App\Services\AuditLogger;
use App\Support\Erp\Permissions;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Roles & permissions. Every built-in role is listed with what it holds,
 * the company's own definition if it has one, otherwise the platform default,
 * next to any roles the company has created for itself.
 */
class RoleController extends Controller
{
    public function __construct(
        private readonly TenantContext $tenant,
        private readonly Permissions $permissions,
        private readonly AuditLogger $audit,
    ) {}

    public function index(): JsonResponse
    {
        $stored = CompanyRole::query()->get()->keyBy('key');
        $counts = User::query()->forTenant($this->tenant->id())->selectRaw('role, COUNT(*) AS c')->groupBy('role')->pluck('c', 'role');

        $builtIn = collect(User::ASSIGNABLE_ROLES)->map(fn (string $key) => [
            'key' => $key,
            'name' => $stored[$key]->name ?? User::roleLabel($key),
            'description' => $stored[$key]->description ?? null,
            'built_in' => true,
            'customised' => isset($stored[$key]),
            'locked' => $key === User::ROLE_COMPANY_ADMIN,
            'permissions' => $key === User::ROLE_COMPANY_ADMIN ? Permissions::all() : ($stored[$key]->permissions ?? Permissions::defaultsFor($key)),
            'users' => (int) ($counts[$key] ?? 0),
        ]);

        $custom = $stored->reject(fn ($r) => in_array($r->key, User::ASSIGNABLE_ROLES, true))->map(fn (CompanyRole $r) => [
            'key' => $r->key,
            'name' => $r->name,
            'description' => $r->description,
            'built_in' => false,
            'customised' => true,
            'locked' => false,
            'permissions' => $r->permissions,
            'users' => (int) ($counts[$r->key] ?? 0),
        ])->values();

        return response()->json([
            'data' => [...$builtIn, ...$custom],
            'catalogue' => collect(Permissions::catalogue())->map(fn ($p, $key) => ['key' => $key, ...$p])->values(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:80'],
            'description' => ['nullable', 'string', 'max:255'],
            'permissions' => ['present', 'array'],
            'permissions.*' => [Rule::in(Permissions::all())],
        ]);

        $key = $this->uniqueKey($data['name']);
        $role = CompanyRole::create([...$data, 'key' => $key, 'company_id' => $this->tenant->id()]);

        $this->audit->log('role.created', "Created role {$role->name}", $role);

        return response()->json(['data' => $role], 201);
    }

    /** Re-scopes a built-in role or edits a custom one. The administrator role is fixed. */
    public function update(Request $request, string $key): JsonResponse
    {
        abort_if($key === User::ROLE_COMPANY_ADMIN, 422, 'The administrator role always holds every permission.');
        abort_if($key === User::ROLE_SUPER_ADMIN, 404);

        $existing = CompanyRole::query()->where('key', $key)->first();
        abort_unless($existing || in_array($key, User::ASSIGNABLE_ROLES, true), 404);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:80'],
            'description' => ['nullable', 'string', 'max:255'],
            'permissions' => ['sometimes', 'array'],
            'permissions.*' => [Rule::in(Permissions::all())],
        ]);

        $before = $existing?->permissions ?? Permissions::defaultsFor($key);

        $role = CompanyRole::updateOrCreate(['key' => $key], [
            'company_id' => $this->tenant->id(),
            'name' => $data['name'] ?? $existing->name ?? User::roleLabel($key),
            'description' => $data['description'] ?? $existing?->description,
            'permissions' => array_values($data['permissions'] ?? $before),
            'is_system' => in_array($key, User::ASSIGNABLE_ROLES, true),
        ]);

        $this->permissions->forget();
        $this->audit->log('role.updated', "Updated permissions for {$role->name}", $role, ['permissions' => $before], ['permissions' => $role->permissions]);

        return response()->json(['data' => $role]);
    }

    /** A built-in role returns to the platform default; a custom role must have nobody in it. */
    public function destroy(string $key): JsonResponse
    {
        $role = CompanyRole::query()->where('key', $key)->firstOrFail();

        if (! $role->is_system) {
            abort_if(
                User::query()->forTenant($this->tenant->id())->where('role', $key)->exists(),
                422,
                "People still hold the {$role->name} role. Move them to another role first.",
            );
        }

        $role->delete();
        $this->permissions->forget();
        $this->audit->log('role.deleted', $role->is_system ? "Restored {$role->name} to its defaults" : "Deleted role {$role->name}", $role);

        return response()->json(['message' => $role->is_system ? "{$role->name} is back to its default permissions." : "{$role->name} deleted."]);
    }

    private function uniqueKey(string $name): string
    {
        $base = substr(str($name)->snake()->replaceMatches('/[^a-z0-9_]/', '')->toString() ?: 'role', 0, 26);
        $taken = [...User::ALL_ROLES, ...CompanyRole::query()->pluck('key')->all()];
        $key = $base;

        for ($i = 2; in_array($key, $taken, true); $i++) {
            $key = "{$base}_{$i}";
        }

        return $key;
    }
}
