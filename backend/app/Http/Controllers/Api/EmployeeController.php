<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Invitations;
use App\Services\UsageLimits;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * Company-scoped user management. Every query is pinned to the resolved tenant, so
 * one company's administrator can never read or write another company's people.
 */
class EmployeeController extends Controller
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly UsageLimits $limits,
        private readonly Invitations $invitations,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request)
    {
        $this->authorizeAdmin($request);

        $users = User::query()
            ->forTenant($this->tenant->id())
            ->with('department')
            ->withCount('vouchers')
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                ->where('name', 'like', "%{$v}%")
                ->orWhere('email', 'like', "%{$v}%")
                ->orWhere('employee_code', 'like', "%{$v}%")))
            ->when($request->query('role'), fn ($q, $v) => $q->where('role', $v))
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('department_id'), fn ($q, $v) => $q->where('department_id', $v))
            ->orderBy('name')
            ->paginate((int) $request->query('per_page', 25))
            ->withQueryString();

        return UserResource::collection($users);
    }

    /** Anyone signed in may look up colleagues to assign as approvers. */
    public function directory(Request $request)
    {
        $users = User::query()
            ->forTenant($this->tenant->id())
            ->where('status', 'active')
            ->when($request->query('role'), fn ($q, $v) => $q->where('role', $v))
            ->orderBy('name')
            ->get(['id', 'name', 'email', 'role', 'job_title', 'department_id']);

        return response()->json([
            'data' => $users->map(fn (User $u) => [
                'id' => $u->id,
                'name' => $u->name,
                'email' => $u->email,
                'role' => $u->role,
                'job_title' => $u->job_title,
                'department_id' => $u->department_id,
            ]),
        ]);
    }

    public function store(Request $request)
    {
        $this->authorizeAdmin($request);
        $this->limits->assertCanAddUser($this->tenant->company());

        $data = $request->validate([
            'name' => ['required', 'string', 'max:180'],
            // Someone removed earlier may be added again: their old row is
            // brought back below rather than blocking the address for good.
            'email' => ['required', 'email', 'max:180', Rule::unique('users')->where('company_id', $this->tenant->id())->whereNull('deleted_at')],
            'phone' => ['nullable', 'string', 'max:40'],
            'employee_code' => ['nullable', 'string', 'max:40'],
            'job_title' => ['nullable', 'string', 'max:120'],
            'role' => ['required', Rule::in(User::ASSIGNABLE_ROLES)],
            'department_id' => ['nullable', 'integer', Rule::exists('departments', 'id')->where('company_id', $this->tenant->id())],
            'password' => ['nullable', 'string', 'min:8'],
            'send_invitation' => ['nullable', 'boolean'],
        ]);

        $invite = $data['send_invitation'] ?? true;
        $password = $data['password'] ?? Str::password(12);
        $data['email'] = mb_strtolower(trim($data['email']));

        $attributes = [
            'company_id' => $this->tenant->id(),
            'name' => $data['name'],
            'email' => $data['email'],
            'phone' => $data['phone'] ?? null,
            'employee_code' => $data['employee_code'] ?? null,
            'job_title' => $data['job_title'] ?? null,
            'role' => $data['role'],
            'department_id' => $data['department_id'] ?? null,
            'password' => $password,
            'status' => $invite ? 'invited' : 'active',
            'locale' => $this->tenant->company()?->locale ?? 'en',
            'invited_at' => null,
            'invitation_token' => null,
        ];

        $user = User::onlyTrashed()->forTenant($this->tenant->id())->where('email', $data['email'])->first();

        if ($user) {
            $user->restore();
            $user->forceFill($attributes + ['last_login_at' => null])->save();
        } else {
            $user = User::create($attributes);
        }

        $this->audit->log('user.created', "Added {$user->name} as {$user->role}", $user);

        // The person chooses their own password from the emailed link. The
        // generated one above only fills the column until they do.
        $invitation = $invite ? $this->invitations->issue($user, $request->user()) : [];

        return (new UserResource($user->refresh()->load('department')))
            ->additional($invitation + [
                'temporary_password' => $invite || app()->environment('production') ? null : $password,
            ])
            ->response()->setStatusCode(201);
    }

    public function show(Request $request, User $user)
    {
        $this->authorizeSameTenant($user);
        $this->authorizeAdminOrSelf($request, $user);

        return new UserResource($user->load('department')->loadCount('vouchers'));
    }

    public function update(Request $request, User $user)
    {
        $this->authorizeAdmin($request);
        $this->authorizeSameTenant($user);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:180'],
            'email' => ['sometimes', 'email', 'max:180', Rule::unique('users')->where('company_id', $this->tenant->id())->ignore($user->id)],
            'phone' => ['nullable', 'string', 'max:40'],
            'employee_code' => ['nullable', 'string', 'max:40'],
            'job_title' => ['nullable', 'string', 'max:120'],
            'role' => ['sometimes', Rule::in(User::ASSIGNABLE_ROLES)],
            'department_id' => ['nullable', 'integer', Rule::exists('departments', 'id')->where('company_id', $this->tenant->id())],
            'status' => ['sometimes', Rule::in(['active', 'invited', 'suspended'])],
        ]);

        // An administrator must not strip the tenant's last administrator.
        if (($data['role'] ?? $user->role) !== 'company_admin' && $user->isCompanyAdmin()) {
            $remaining = User::forTenant($this->tenant->id())
                ->where('role', 'company_admin')
                ->where('id', '!=', $user->id)
                ->count();

            abort_if($remaining === 0, 422, 'A company must keep at least one administrator.');
        }

        $before = $user->only(['role', 'status', 'department_id']);
        $user->update($data);

        if (($data['status'] ?? null) === 'suspended') {
            $user->tokens()->delete();
        }

        $this->audit->log(
            'user.updated',
            "Updated {$user->name}",
            $user,
            $before,
            $user->only(['role', 'status', 'department_id']),
        );

        return new UserResource($user->fresh()->load('department'));
    }

    public function destroy(Request $request, User $user)
    {
        $this->authorizeAdmin($request);
        $this->authorizeSameTenant($user);

        abort_if($user->id === $request->user()->id, 422, 'You cannot remove your own account.');

        if ($user->isCompanyAdmin()) {
            $remaining = User::forTenant($this->tenant->id())->where('role', 'company_admin')->where('id', '!=', $user->id)->count();
            abort_if($remaining === 0, 422, 'A company must keep at least one administrator.');
        }

        $name = $user->name;
        $user->tokens()->delete();
        $user->delete();

        $this->audit->log('user.deleted', "Removed {$name}", $user);

        return response()->json(['message' => "{$name} removed."]);
    }

    public function resendInvitation(Request $request, User $user)
    {
        $this->authorizeAdmin($request);
        $this->authorizeSameTenant($user);

        abort_if($user->status === 'suspended', 422, 'Activate this person before sending them a new link.');

        // Their password is left alone: someone already using the account
        // keeps it until they choose a new one from the link.
        if (! $user->last_login_at) {
            $user->forceFill(['status' => 'invited'])->save();
        }

        $invitation = $this->invitations->issue($user, $request->user());

        $this->audit->log('user.invited', "Re-invited {$user->name}", $user);

        return response()->json($invitation + [
            'message' => $invitation['invitation_sent']
                ? "A new invitation is on its way to {$user->email}."
                : 'The invitation email could not be sent. Share the link instead.',
        ]);
    }

    private function authorizeAdmin(Request $request): void
    {
        abort_unless($request->user()->isAdmin(), 403, 'Only an administrator may manage people.');
    }

    private function authorizeAdminOrSelf(Request $request, User $user): void
    {
        abort_unless(
            $request->user()->isAdmin() || $request->user()->id === $user->id,
            403,
            'You may only view your own profile.',
        );
    }

    /** Belt and braces: User carries no global tenant scope, so check explicitly. */
    private function authorizeSameTenant(User $user): void
    {
        abort_unless($user->company_id === $this->tenant->id(), 404);
    }
}
