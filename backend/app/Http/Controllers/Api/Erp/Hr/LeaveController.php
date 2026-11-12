<?php

namespace App\Http\Controllers\Api\Erp\Hr;

use App\Http\Controllers\Controller;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\LeaveBalance;
use App\Models\Erp\Hr\LeaveRequest;
use App\Models\Erp\Hr\LeaveType;
use App\Services\AuditLogger;
use App\Services\Erp\Hr\HrAccess;
use App\Services\Erp\Hr\LeaveService;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/**
 * Leave requests, approvals, the calendar of who is away, balances and types.
 * HR (hr.view) sees the whole company; an approver without it sees their team.
 */
class LeaveController extends Controller
{
    public function __construct(private readonly LeaveService $leave, private readonly TenantContext $tenant) {}

    public function types(): JsonResponse
    {
        $this->leave->ensureTypes();

        return response()->json(['data' => LeaveType::query()->orderBy('id')->get()]);
    }

    public function storeType(Request $request): JsonResponse
    {
        $type = LeaveType::create($this->typeData($request, null));

        return response()->json(['message' => 'Leave type saved.', 'data' => $type], 201);
    }

    public function updateType(Request $request, LeaveType $leaveType): JsonResponse
    {
        $leaveType->update($this->typeData($request, $leaveType));

        return response()->json(['message' => 'Leave type saved.', 'data' => $leaveType]);
    }

    public function index(Request $request): JsonResponse
    {
        $rows = $this->visible($request)
            ->with('employee:id,full_name,employee_number,department_id', 'employee.department:id,name', 'leaveType:id,name,code,paid', 'decider:id,name')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('employee_id'), fn ($q, $v) => $q->where('employee_id', $v))
            ->when($request->query('leave_type_id'), fn ($q, $v) => $q->where('leave_type_id', $v))
            ->orderByRaw("case when status = 'pending' then 0 else 1 end")->latest('start_date')
            ->paginate(min((int) $request->query('per_page', 30), 100));

        $user = $request->user();
        $rows->getCollection()->transform(fn (LeaveRequest $r) => [...$r->toArray(), 'can_decide' => $r->status === LeaveRequest::STATUS_PENDING && $this->leave->canDecide($user, $r)]);

        return response()->json($rows);
    }

    /** HR files a request for someone (e.g. sick leave phoned in). */
    public function store(Request $request): JsonResponse
    {
        $data = $this->requestData($request, true);
        $employee = Employee::query()->findOrFail($data['employee_id']);

        return response()->json(['message' => 'Leave requested.', 'data' => $this->leave->request($employee, $data, $request->user())], 201);
    }

    public function approve(Request $request, LeaveRequest $leaveRequest): JsonResponse
    {
        $note = $request->validate(['note' => ['nullable', 'string', 'max:500']])['note'] ?? null;

        return response()->json(['message' => 'Leave approved.', 'data' => $this->leave->approve($leaveRequest, $request->user(), $note)]);
    }

    public function reject(Request $request, LeaveRequest $leaveRequest): JsonResponse
    {
        $note = $request->validate(['note' => ['required', 'string', 'min:3', 'max:500']])['note'];

        return response()->json(['message' => 'Leave rejected.', 'data' => $this->leave->reject($leaveRequest, $request->user(), $note)]);
    }

    public function cancel(Request $request, LeaveRequest $leaveRequest): JsonResponse
    {
        return response()->json(['message' => 'Leave cancelled.', 'data' => $this->leave->cancel($leaveRequest, $request->user())]);
    }

    /** Who is away in a month: approved and pending requests overlapping it. */
    public function calendar(Request $request): JsonResponse
    {
        $month = (string) $request->query('month', today()->format('Y-m'));
        abort_unless((bool) preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $month), 422, 'A month is written as YYYY-MM.');
        $from = Carbon::parse("{$month}-01");
        $to = $from->copy()->endOfMonth();

        $rows = $this->visible($request)
            ->with('employee:id,full_name,department_id', 'employee.department:id,name', 'leaveType:id,name,code')
            ->whereIn('status', [LeaveRequest::STATUS_APPROVED, LeaveRequest::STATUS_PENDING])
            ->whereDate('start_date', '<=', $to)->whereDate('end_date', '>=', $from)
            ->orderBy('start_date')->get();

        return response()->json(['month' => $month, 'data' => $rows]);
    }

    /** Every active employee's balances for a year. */
    public function balances(Request $request): JsonResponse
    {
        $year = (int) $request->query('year', now()->year);
        $this->leave->ensureTypes();

        $employees = Employee::query()->where('status', Employee::STATUS_ACTIVE)
            ->when($request->query('employee_id'), fn ($q, $v) => $q->whereKey($v))
            ->when($request->query('department_id'), fn ($q, $v) => $q->where('department_id', $v))
            ->orderBy('full_name')->get();

        return response()->json([
            'year' => $year,
            'types' => LeaveType::query()->where('is_active', true)->orderBy('id')->get(['id', 'code', 'name', 'days_per_year']),
            'data' => $employees->map(fn (Employee $e) => [
                'employee' => ['id' => $e->id, 'full_name' => $e->full_name, 'employee_number' => $e->employee_number],
                'balances' => $this->leave->balancesFor($e, $year),
            ])->values(),
        ]);
    }

    public function adjustBalance(Request $request, LeaveBalance $leaveBalance, AuditLogger $audit): JsonResponse
    {
        $data = $request->validate([
            'adjustment' => ['sometimes', 'numeric', 'between:-366,366'],
            'carried_forward' => ['sometimes', 'numeric', 'between:0,366'],
            'reason' => ['required', 'string', 'min:3', 'max:255'],
        ]);
        $before = $leaveBalance->only(['adjustment', 'carried_forward']);
        $leaveBalance->update(array_intersect_key($data, array_flip(['adjustment', 'carried_forward'])));
        $audit->log('hr.leave.balance_adjusted', "Adjusted {$leaveBalance->leaveType->name} {$leaveBalance->year} for {$leaveBalance->employee->full_name}: {$data['reason']}", $leaveBalance, $before, $leaveBalance->only(['adjustment', 'carried_forward']));

        return response()->json(['message' => 'Balance adjusted.', 'data' => $this->leave->describe($leaveBalance->fresh())]);
    }

    /** HR sees all; an approver sees their team; anyone else nothing. */
    private function visible(Request $request): Builder
    {
        $user = $request->user();
        $query = LeaveRequest::query();

        if ($user->hasPermission('hr.view')) {
            return $query;
        }

        abort_unless($user->hasPermission('hr.leave.approve'), 403, 'Your role does not allow you to see other people\'s leave.');
        $team = HrAccess::teamEmployeeIds($user);

        return $team === null ? $query : $query->whereIn('employee_id', $team ?: [0]);
    }

    /** @return array<string, mixed> */
    private function typeData(Request $request, ?LeaveType $type): array
    {
        return $request->validate([
            'code' => [$type ? 'sometimes' : 'required', 'string', 'max:20', 'alpha_dash', Rule::unique('hr_leave_types', 'code')->where('company_id', $this->tenant->id())->ignore($type?->id)],
            'name' => [$type ? 'sometimes' : 'required', 'string', 'max:80'],
            'days_per_year' => ['nullable', 'numeric', 'between:0,366'],
            'paid' => ['sometimes', 'boolean'],
            'accrues_monthly' => ['sometimes', 'boolean'],
            'counting' => ['sometimes', Rule::in(['working', 'calendar'])],
            'is_active' => ['sometimes', 'boolean'],
        ]);
    }

    /** @return array<string, mixed> */
    private function requestData(Request $request, bool $forSomeone): array
    {
        $company = $this->tenant->id();

        return $request->validate([
            ...($forSomeone ? ['employee_id' => ['required', 'integer', Rule::exists('hr_employees', 'id')->where('company_id', $company)]] : []),
            'leave_type_id' => ['required', 'integer', Rule::exists('hr_leave_types', 'id')->where('company_id', $company)],
            'start_date' => ['required', 'date'],
            'end_date' => ['required', 'date'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);
    }
}
