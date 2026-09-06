<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\DepartmentResource;
use App\Models\Department;
use App\Models\User;
use App\Models\Voucher;
use App\Services\AuditLogger;
use App\Services\UsageLimits;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class DepartmentController extends Controller
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly UsageLimits $limits,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request)
    {
        $departments = Department::with(['hod', 'manager'])
            ->withCount(['users', 'vouchers'])
            ->when($request->query('q'), fn ($q, $v) => $q->where('name', 'like', "%{$v}%"))
            ->orderBy('name')
            ->get();

        // Quarter-to-date spend, as shown on the departments screen.
        $spend = Voucher::query()
            ->where('status', Voucher::STATUS_APPROVED)
            ->whereBetween('voucher_date', [now()->firstOfQuarter(), now()->lastOfQuarter()])
            ->selectRaw('department_id, SUM(amount) as total')
            ->groupBy('department_id')
            ->pluck('total', 'department_id');

        $departments->each(fn (Department $d) => $d->spend = (float) ($spend[$d->id] ?? 0));

        return DepartmentResource::collection($departments);
    }

    public function store(Request $request)
    {
        $this->authorizeAdmin($request);
        $this->limits->assertCanAddDepartment($this->tenant->company());

        $data = $this->rules($request);
        $department = Department::create($data);

        $this->audit->log('department.created', "Created department {$department->name}", $department);

        return (new DepartmentResource($department->load(['hod', 'manager'])))->response()->setStatusCode(201);
    }

    public function show(Department $department)
    {
        return new DepartmentResource($department->load(['hod', 'manager'])->loadCount(['users', 'vouchers']));
    }

    public function update(Request $request, Department $department)
    {
        $this->authorizeAdmin($request);

        $before = $department->only(['name', 'hod_user_id', 'manager_user_id', 'cost_centre']);
        $department->update($this->rules($request, $department->id));

        $this->audit->log(
            'department.updated',
            "Updated department {$department->name}",
            $department,
            $before,
            $department->only(['name', 'hod_user_id', 'manager_user_id', 'cost_centre']),
        );

        return new DepartmentResource($department->fresh()->load(['hod', 'manager']));
    }

    public function destroy(Request $request, Department $department)
    {
        $this->authorizeAdmin($request);

        abort_if(
            $department->vouchers()->exists(),
            422,
            'This department has vouchers on record and cannot be deleted. Deactivate it instead.',
        );

        $name = $department->name;
        User::where('department_id', $department->id)->update(['department_id' => null]);
        $department->delete();

        $this->audit->log('department.deleted', "Deleted department {$name}", $department);

        return response()->json(['message' => "Department {$name} deleted."]);
    }

    private function rules(Request $request, ?int $ignoreId = null): array
    {
        return $request->validate([
            'name' => [
                'required', 'string', 'max:120',
                Rule::unique('departments')
                    ->where('company_id', $this->tenant->id())
                    ->ignore($ignoreId),
            ],
            'code' => ['nullable', 'string', 'max:30'],
            'cost_centre' => ['nullable', 'string', 'max:60'],
            'hod_user_id' => ['nullable', 'integer', Rule::exists('users', 'id')->where('company_id', $this->tenant->id())],
            'manager_user_id' => ['nullable', 'integer', Rule::exists('users', 'id')->where('company_id', $this->tenant->id())],
            'is_active' => ['nullable', 'boolean'],
        ]);
    }

    private function authorizeAdmin(Request $request): void
    {
        abort_unless($request->user()->isAdmin(), 403, 'Only an administrator may change departments.');
    }
}
