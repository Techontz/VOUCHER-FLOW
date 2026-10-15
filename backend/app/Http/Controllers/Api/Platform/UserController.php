<?php

namespace App\Http\Controllers\Api\Platform;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
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

    public function destroy(Request $request, User $user)
    {
        $result = $this->remove($request->user(), collect([$user]));

        abort_if($result['skipped'] !== [], 422, $result['skipped'][0]['reason'] ?? 'This account cannot be deleted.');

        return response()->json(['message' => "{$user->name} deleted."]);
    }

    /** Deletes several accounts; any that must stay are named with the reason. */
    public function bulkDestroy(Request $request)
    {
        $data = $request->validate([
            'ids' => ['required', 'array', 'min:1', 'max:500'],
            'ids.*' => ['integer'],
        ]);

        $result = $this->remove($request->user(), User::with('company')->whereIn('id', $data['ids'])->get());

        $count = $result['deleted'];

        return response()->json([
            'deleted' => $count,
            'skipped' => $result['skipped'],
            'message' => $count === 1 ? '1 user deleted.' : "{$count} users deleted.",
        ]);
    }

    /**
     * Signs each account out and deletes it. Vouchers they raised or acted on
     * stay on the record. Refused: the caller's own account, the platform's
     * last operator, and the last administrator of a company that still exists
     * (delete the company itself instead).
     *
     * @param  Collection<int, User>  $users
     * @return array{deleted: int, skipped: array<int, array{id: int, name: string, reason: string}>}
     */
    private function remove(User $actor, Collection $users): array
    {
        // The caller is never deleted, so they count among those who stay.
        $ids = $users->pluck('id')->reject(fn (int $id) => $id === $actor->id)->values()->all();
        $deleted = 0;
        $skipped = [];

        foreach ($users as $user) {
            $reason = $this->keepReason($actor, $user, $ids);

            if ($reason) {
                $skipped[] = ['id' => $user->id, 'name' => $user->name, 'reason' => $reason];

                continue;
            }

            $user->tokens()->delete();
            $user->delete();
            $deleted++;

            $this->audit->log('platform.user_deleted', "Deleted {$user->name} ({$user->email})", $user, null, null, $user->company_id);
        }

        return ['deleted' => $deleted, 'skipped' => $skipped];
    }

    /** @param  array<int, int>  $removing */
    private function keepReason(User $actor, User $user, array $removing): ?string
    {
        if ($user->id === $actor->id) {
            return 'You cannot delete your own account.';
        }

        if ($user->isSuperAdmin()) {
            $others = User::where('role', User::ROLE_SUPER_ADMIN)->where('status', 'active')
                ->whereNotIn('id', $removing)->count();

            return $others === 0 ? 'The platform must keep at least one operator.' : null;
        }

        if ($user->isCompanyAdmin() && $user->company) {
            $others = User::forTenant($user->company_id)->where('role', 'company_admin')
                ->whereNotIn('id', $removing)->count();

            return $others === 0
                ? "{$user->company->name} must keep at least one administrator. Delete the company instead."
                : null;
        }

        return null;
    }
}
