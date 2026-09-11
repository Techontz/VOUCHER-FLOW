<?php

namespace App\Http\Controllers\Api\Platform;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Every user on the platform, across all tenants. */
class UserController extends Controller
{
    public function __construct(private readonly AuditLogger $audit) {}

    public function index(Request $request)
    {
        $users = User::query()
            ->with(['company', 'department'])
            ->when($request->query('company_id'), fn ($q, $v) => $q->where('company_id', $v))
            ->when($request->query('role'), fn ($q, $v) => $q->where('role', $v))
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                ->where('name', 'like', "%{$v}%")->orWhere('email', 'like', "%{$v}%")))
            ->orderBy('name')
            ->paginate((int) $request->query('per_page', 25))
            ->withQueryString();

        return UserResource::collection($users);
    }

    public function update(Request $request, User $user)
    {
        $data = $request->validate([
            'status' => ['sometimes', Rule::in(['active', 'invited', 'suspended'])],
            'role' => ['sometimes', Rule::in(User::ALL_ROLES)],
        ]);

        $before = $user->only(['role', 'status']);
        $user->update($data);

        if (($data['status'] ?? null) === 'suspended') {
            $user->tokens()->delete();
        }

        $this->audit->log('platform.user_updated', "Updated {$user->name}", $user, $before, $user->only(['role', 'status']), $user->company_id);

        return new UserResource($user->fresh()->load(['company', 'department']));
    }
}
