<?php

namespace App\Http\Controllers\Api\Platform;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\Company;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Invitations;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Validation\Rule;
use RuntimeException;

/** Every user on the platform, across all tenants. */
class UserController extends Controller
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly Invitations $invitations,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request)
    {
        $users = User::query()
            ->with(['company', 'department'])
            ->when($request->query('company_id'), fn ($q, $v) => $v === 'platform'
                ? $q->whereNull('company_id')
                : $q->where('company_id', $v))
            ->when($request->query('role'), fn ($q, $v) => $q->where('role', $v))
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                ->where('name', 'like', "%{$v}%")->orWhere('email', 'like', "%{$v}%")))
            ->when($request->query('sort') === 'recent', fn ($q) => $q->latest('id'), fn ($q) => $q->orderBy('name'))
            ->paginate((int) $request->query('per_page', 25))
            ->withQueryString();

        return UserResource::collection($users);
    }

    /**
     * Changes an account's status or role.
     *
     * Never the caller's own account, never the platform's last active
     * operator, and never a company's last active administrator. A company
     * user's role comes from that company's vocabulary (built-in roles plus
     * its own); a platform operator has no company and keeps their role.
     */
    public function update(Request $request, User $user)
    {
        $data = $request->validate([
            'status' => ['sometimes', Rule::in(['active', 'suspended'])],
            'role' => ['sometimes', 'string', 'max:60'],
        ]);

        $actor = $request->user();
        abort_if($user->id === $actor->id, 422, 'You cannot change your own account here.');

        if (array_key_exists('role', $data) && $data['role'] !== $user->role) {
            $this->assertRoleChange($user, $data['role']);
        }

        if (($data['status'] ?? null) === 'suspended' && $user->status !== 'suspended') {
            $reason = $this->suspendReason($user, [$user->id]);
            abort_if($reason !== null, 422, $reason ?? '');
        }

        $before = $user->only(['role', 'status']);
        $user->forceFill($data)->save();

        if (($data['status'] ?? null) === 'suspended') {
            $user->tokens()->delete();
        }

        $this->audit->log('platform.user_updated', "Updated {$user->name}", $user, $before, $user->only(['role', 'status']), $user->company_id);

        return new UserResource($user->fresh()->load(['company', 'department']));
    }

    /** Suspends or reactivates several accounts; any that must stay as they are are named with the reason. */
    public function bulkStatus(Request $request)
    {
        $data = $request->validate([
            'ids' => ['required', 'array', 'min:1', 'max:500'],
            'ids.*' => ['integer'],
            'status' => ['required', Rule::in(['active', 'suspended'])],
        ]);

        $actor = $request->user();
        $users = User::with('company')->whereIn('id', $data['ids'])->get();
        $changing = $users->pluck('id')->all();
        $done = 0;
        $skipped = [];

        foreach ($users as $user) {
            $reason = match (true) {
                $user->id === $actor->id => 'You cannot change your own account here.',
                $user->status === $data['status'] => null,
                $data['status'] === 'suspended' => $this->suspendReason($user, $changing),
                default => null,
            };

            if ($reason) {
                $skipped[] = ['id' => $user->id, 'name' => $user->name, 'reason' => $reason];

                continue;
            }

            if ($user->status === $data['status']) {
                continue;
            }

            $before = $user->only(['status']);
            $user->forceFill(['status' => $data['status']])->save();

            if ($data['status'] === 'suspended') {
                $user->tokens()->delete();
            }

            $this->audit->log('platform.user_updated', "Updated {$user->name}", $user, $before, $user->only(['status']), $user->company_id);
            $done++;
        }

        $verb = $data['status'] === 'suspended' ? 'suspended' : 'activated';

        return response()->json([
            'updated' => $done,
            'skipped' => $skipped,
            'message' => $done === 1 ? "1 user {$verb}." : "{$done} users {$verb}.",
        ]);
    }

    /**
     * Sends a fresh link to choose a password: the invitation for someone who
     * never signed in, a reset for anyone else. The same link either way; the
     * operator is handed it too, in case the email does not arrive.
     */
    public function invite(Request $request, User $user)
    {
        abort_if($user->id === $request->user()->id, 422, 'Change your own password from your profile.');
        abort_if($user->status === 'suspended', 422, 'Activate this person before sending them a link.');
        abort_if(! $user->company_id || ! $user->company, 422,
            'Platform operators reset their password from the sign-in page with "Forgot password".');

        if (! $user->last_login_at) {
            $user->forceFill(['status' => 'invited'])->save();
        }

        $invitation = $this->invitations->issue($user, $request->user());

        $this->audit->log('platform.user_invited', "Sent {$user->name} a link to set a password", $user, null, null, $user->company_id);

        return response()->json($invitation + [
            'message' => $invitation['invitation_sent']
                ? "A link to set a password is on its way to {$user->email}."
                : 'The email could not be sent. Share the link instead.',
        ]);
    }

    /** The roles an account may be given, for the change-role menu. */
    public function roles(Request $request)
    {
        $companyId = $request->integer('company_id') ?: null;
        $company = $companyId ? Company::find($companyId) : null;

        $roles = $company
            ? $this->tenant->forCompany($company, fn () => User::assignableRoles())
            : User::ASSIGNABLE_ROLES;

        return response()->json([
            'data' => collect($roles)->map(fn (string $r) => ['key' => $r, 'label' => User::roleLabel($r)])->values(),
        ]);
    }

    private function assertRoleChange(User $user, string $role): void
    {
        if ($user->isSuperAdmin() || ! $user->company_id) {
            throw new RuntimeException('A platform operator has no company, so their role cannot be changed.');
        }

        if ($role === User::ROLE_SUPER_ADMIN) {
            throw new RuntimeException('Platform access cannot be granted to a company account.');
        }

        $company = $user->company;
        $allowed = $company
            ? $this->tenant->forCompany($company, fn () => User::assignableRoles())
            : User::ASSIGNABLE_ROLES;

        if (! in_array($role, $allowed, true)) {
            throw new RuntimeException("{$role} is not a role this company uses.");
        }

        if ($user->isCompanyAdmin() && $this->otherActiveAdmins($user, [$user->id]) === 0) {
            throw new RuntimeException(($company?->name ?? 'This company').' must keep at least one active administrator.');
        }
    }

    /** @param  array<int, int>  $changing */
    private function suspendReason(User $user, array $changing): ?string
    {
        if ($user->isSuperAdmin()) {
            $others = User::where('role', User::ROLE_SUPER_ADMIN)->where('status', 'active')
                ->whereNotIn('id', $changing)->count();

            return $others === 0 ? 'The platform must keep at least one active operator.' : null;
        }

        if ($user->isCompanyAdmin() && $user->company && $this->otherActiveAdmins($user, $changing) === 0) {
            return "{$user->company->name} must keep at least one active administrator.";
        }

        return null;
    }

    /** @param  array<int, int>  $excluding */
    private function otherActiveAdmins(User $user, array $excluding): int
    {
        return User::forTenant($user->company_id)->where('role', User::ROLE_COMPANY_ADMIN)
            ->where('status', 'active')->whereNotIn('id', $excluding)->count();
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
