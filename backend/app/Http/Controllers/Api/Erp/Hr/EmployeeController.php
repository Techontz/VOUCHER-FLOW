<?php

namespace App\Http\Controllers\Api\Erp\Hr;

use App\Http\Controllers\Controller;
use App\Http\Resources\Erp\Hr\ContractResource;
use App\Http\Resources\Erp\Hr\EmployeeResource;
use App\Http\Resources\Erp\Hr\SeparationResource;
use App\Models\Erp\Hr\Appraisal;
use App\Models\Erp\Hr\Attendance;
use App\Models\Erp\Hr\Contract;
use App\Models\Erp\Hr\DisciplineCase;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\LeaveRequest;
use App\Models\Erp\Hr\Movement;
use App\Models\Erp\Hr\OnboardingTask;
use App\Models\Erp\Hr\Payslip;
use App\Models\Erp\Hr\Separation;
use App\Models\Erp\Hr\Training;
use App\Models\User;
use App\Services\Erp\Hr\EmployeeService;
use App\Services\Erp\Hr\HrAccess;
use App\Services\Erp\Hr\LeaveService;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

/**
 * Employee records, contracts, transfers and promotions, and onboarding.
 *
 * Salary and bank details are field-level: they reach the response only for
 * hr.salary, and only hr.salary may write them. Disciplinary cases appear on
 * a profile only for hr.discipline.
 */
class EmployeeController extends Controller
{
    public function __construct(
        private readonly EmployeeService $employees,
        private readonly LeaveService $leave,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        $rows = Employee::query()->with(['department:id,name', 'activeContract', 'user:id,name,email,role'])
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v), fn ($q) => $q->where('status', '!=', Employee::STATUS_EXITED))
            ->when($request->query('department_id'), fn ($q, $v) => $q->where('department_id', $v))
            ->when($request->query('employment_type'), fn ($q, $v) => $q->where('employment_type', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('full_name', 'like', "%{$v}%")
                ->orWhere('employee_number', 'like', "%{$v}%")->orWhere('job_title', 'like', "%{$v}%")->orWhere('phone', 'like', "%{$v}%")))
            ->orderBy('full_name')
            ->paginate(min((int) $request->query('per_page', 30), 200));

        return EmployeeResource::collection($rows);
    }

    public function show(Request $request, Employee $employee): JsonResponse
    {
        $user = $request->user();
        $employee->load(['department:id,name', 'manager:id,full_name', 'shift:id,name', 'user:id,name,email,role', 'activeContract']);

        return response()->json([
            'data' => new EmployeeResource($employee),
            'contracts' => ContractResource::collection($employee->contracts()->orderByDesc('start_date')->get()),
            'movements' => Movement::query()->with('fromDepartment:id,name', 'toDepartment:id,name', 'creator:id,name')
                ->where('employee_id', $employee->id)->orderByDesc('effective_date')->get(),
            'onboarding' => $employee->onboardingTasks()->with('doer:id,name')->get(),
            'leave_balances' => $this->leave->balancesFor($employee, (int) $request->query('year', now()->year)),
            'leave_requests' => LeaveRequest::query()->with('leaveType:id,name')->where('employee_id', $employee->id)->latest('start_date')->limit(20)->get(),
            'attendance' => Attendance::query()->where('employee_id', $employee->id)->whereDate('date', '>=', today()->subDays(30))->orderByDesc('date')->get(),
            'trainings' => Training::query()->where('employee_id', $employee->id)->orderByDesc('start_date')->get(),
            'appraisals' => Appraisal::query()->with('period:id,name')->where('employee_id', $employee->id)->latest('id')->get(['id', 'period_id', 'status', 'overall_rating', 'completed_at']),
            'exit' => ($s = Separation::query()->with('items.clearer:id,name')->where('employee_id', $employee->id)->latest('id')->first()) ? new SeparationResource($s) : null,
            'payslips' => HrAccess::seesSalary($user) || HrAccess::worksOnPayroll($user)
                ? Payslip::query()->with('run:id,number,period,status')->where('employee_id', $employee->id)->latest('id')->limit(12)
                    ->get(['id', 'payroll_run_id', 'gross', 'net', 'total_deductions'])
                : null,
            'discipline' => HrAccess::seesDiscipline($user)
                ? DisciplineCase::query()->where('employee_id', $employee->id)->latest('incident_date')->get()
                : null,
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validated($request, null);
        $contract = $this->contractData($request);

        $employee = $this->employees->create($data, $contract, $request->user());

        return response()->json(['message' => "{$employee->full_name} added.", 'data' => new EmployeeResource($employee->load('department', 'activeContract'))], 201);
    }

    public function update(Request $request, Employee $employee): JsonResponse
    {
        $data = $this->validated($request, $employee);
        $employee = $this->employees->update($employee, $data, $request->user());

        return response()->json(['message' => 'Employee saved.', 'data' => new EmployeeResource($employee->load('department', 'activeContract'))]);
    }

    public function storeContract(Request $request, Employee $employee): JsonResponse
    {
        abort_unless($request->user()->hasPermission('hr.manage'), 403, 'Changing contracts needs the employee records permission.');
        $contract = $this->employees->newContract($employee, $this->contractData($request, true), $request->user());

        return response()->json(['message' => 'Contract started.', 'data' => new ContractResource($contract)], 201);
    }

    public function storeMovement(Request $request, Employee $employee): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'type' => ['required', Rule::in(Movement::TYPES)],
            'effective_date' => ['required', 'date'],
            'to_department_id' => ['nullable', 'integer', Rule::exists('departments', 'id')->where('company_id', $company)],
            'to_job_title' => ['nullable', 'string', 'max:120'],
            'to_grade' => ['nullable', 'string', 'max:20'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        $movement = $this->employees->move($employee, $data, $request->user());

        return response()->json(['message' => 'Change recorded.', 'data' => $movement->load('fromDepartment:id,name', 'toDepartment:id,name')], 201);
    }

    public function linkableUsers(): JsonResponse
    {
        $linked = Employee::query()->whereNotNull('user_id')->pluck('user_id');

        return response()->json(['data' => User::query()->forTenant($this->tenant->id())
            ->whereNotIn('id', $linked)->orderBy('name')
            ->get(['id', 'name', 'email', 'role', 'job_title', 'department_id', 'phone', 'employee_code'])]);
    }

    public function storeTask(Request $request, Employee $employee): JsonResponse
    {
        $data = $request->validate(['title' => ['required', 'string', 'max:255']]);
        $task = $employee->onboardingTasks()->create(['title' => $data['title'], 'sort' => (int) $employee->onboardingTasks()->max('sort') + 1]);

        return response()->json(['data' => $task], 201);
    }

    public function updateTask(Request $request, OnboardingTask $task): JsonResponse
    {
        $done = $request->validate(['done' => ['required', 'boolean']])['done'];
        $task->update($done ? ['done_at' => now(), 'done_by' => $request->user()->id] : ['done_at' => null, 'done_by' => null]);

        return response()->json(['data' => $task->load('doer:id,name')]);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, ?Employee $employee): array
    {
        $company = $this->tenant->id();
        $creating = $employee === null;
        $required = $creating ? 'required' : 'sometimes';

        $rules = [
            'full_name' => [$required, 'string', 'max:160'],
            'email' => ['nullable', 'email', 'max:160'],
            'phone' => ['nullable', 'string', 'max:40'],
            'national_id' => ['nullable', 'string', 'max:40'],
            'tin' => ['nullable', 'string', 'max:40'],
            'nssf_number' => ['nullable', 'string', 'max:40'],
            'date_of_birth' => ['nullable', 'date', 'before:today'],
            'gender' => ['nullable', Rule::in(['female', 'male'])],
            'address' => ['nullable', 'string', 'max:255'],
            'next_of_kin_name' => ['nullable', 'string', 'max:160'],
            'next_of_kin_phone' => ['nullable', 'string', 'max:40'],
            'next_of_kin_relation' => ['nullable', 'string', 'max:60'],
            'employment_type' => [$required, Rule::in(Employee::EMPLOYMENT_TYPES)],
            'manager_id' => ['nullable', 'integer', Rule::exists('hr_employees', 'id')->where('company_id', $company)],
            'shift_id' => ['nullable', 'integer', Rule::exists('hr_shifts', 'id')->where('company_id', $company)],
            'hire_date' => [$required, 'date'],
            'probation_end' => ['nullable', 'date'],
            'heslb_beneficiary' => ['sometimes', 'boolean'],
            'bank_name' => ['nullable', 'string', 'max:120'],
            'bank_account_number' => ['nullable', 'string', 'max:60'],
        ];

        if ($creating) {
            $rules += [
                'employee_number' => ['nullable', 'string', 'max:40', Rule::unique('hr_employees', 'employee_number')->where('company_id', $company)],
                'user_id' => ['nullable', 'integer', Rule::exists('users', 'id')->where('company_id', $company)],
                'job_title' => ['nullable', 'string', 'max:120'],
                'grade' => ['nullable', 'string', 'max:20'],
                'department_id' => ['nullable', 'integer', Rule::exists('departments', 'id')->where('company_id', $company)],
            ];
        } else {
            $rules['status'] = ['sometimes', Rule::in([Employee::STATUS_ACTIVE, Employee::STATUS_SUSPENDED])];
        }

        $data = $request->validate($rules);

        // Bank details are salary data: only hr.salary may write them.
        if (! HrAccess::seesSalary($request->user())) {
            abort_if(array_filter(array_intersect_key($data, array_flip(EmployeeService::BANK))) !== [], 403, 'Bank details need the salary permission.');
            $data = array_diff_key($data, array_flip(EmployeeService::BANK));
        }

        return $data;
    }

    /** @return array<string, mixed>|null */
    private function contractData(Request $request, bool $required = false): ?array
    {
        if (! $required && ! $request->filled('contract')) {
            return null;
        }

        abort_unless(HrAccess::seesSalary($request->user()), 403, 'Setting pay needs the salary permission.');

        $prefix = $required ? '' : 'contract.';
        $data = $request->validate([
            "{$prefix}type" => ['required', Rule::in(Contract::TYPES)],
            "{$prefix}start_date" => ['required', 'date'],
            "{$prefix}end_date" => ['nullable', 'date'],
            "{$prefix}basic_salary" => ['required', 'numeric', 'min:0', 'max:999999999'],
            "{$prefix}housing_allowance" => ['nullable', 'numeric', 'min:0', 'max:999999999'],
            "{$prefix}transport_allowance" => ['nullable', 'numeric', 'min:0', 'max:999999999'],
            "{$prefix}other_allowance" => ['nullable', 'numeric', 'min:0', 'max:999999999'],
            "{$prefix}notes" => ['nullable', 'string', 'max:500'],
        ]);

        return $required ? $data : $data['contract'];
    }
}
