<?php

namespace App\Http\Controllers\Api\Erp\Hr;

use App\Http\Controllers\Controller;
use App\Models\Erp\Hr\Attendance;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\LeaveRequest;
use App\Models\Erp\Hr\Shift;
use App\Services\AuditLogger;
use App\Services\Erp\Hr\AttendanceService;
use App\Services\Erp\Hr\HrAccess;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * Daily attendance, biometric import, the monthly summary payroll uses, and
 * shifts. HR sees everyone; a department head sees their own team (the
 * team/* routes).
 */
class AttendanceController extends Controller
{
    public function __construct(private readonly AttendanceService $attendance, private readonly TenantContext $tenant) {}

    /** Everyone due at work on a day, with what was recorded and who is on leave. */
    public function daily(Request $request): JsonResponse
    {
        $date = Carbon::parse($request->query('date', today()->toDateString()))->startOfDay();
        $scope = $this->scope($request);

        $employees = Employee::query()->with('department:id,name', 'shift:id,name')
            ->where('status', Employee::STATUS_ACTIVE)->whereDate('hire_date', '<=', $date)
            ->when($scope !== null, fn ($q) => $q->whereIn('id', $scope ?: [0]))
            ->when($request->query('department_id'), fn ($q, $v) => $q->where('department_id', $v))
            ->orderBy('full_name')->get();

        $records = Attendance::query()->whereDate('date', $date)->whereIn('employee_id', $employees->pluck('id'))->get()->keyBy('employee_id');
        $leave = LeaveRequest::query()->with('leaveType:id,name')->where('status', LeaveRequest::STATUS_APPROVED)
            ->whereDate('start_date', '<=', $date)->whereDate('end_date', '>=', $date)
            ->whereIn('employee_id', $employees->pluck('id'))->get()->keyBy('employee_id');

        return response()->json([
            'date' => $date->toDateString(),
            'data' => $employees->map(fn (Employee $e) => [
                'employee' => ['id' => $e->id, 'full_name' => $e->full_name, 'employee_number' => $e->employee_number, 'department' => $e->department?->name, 'shift' => $e->shift?->name],
                'record' => $records[$e->id] ?? null,
                'on_leave' => isset($leave[$e->id]) ? $leave[$e->id]->leaveType?->name : null,
            ])->values(),
        ]);
    }

    /** Per person, the month's attendance in figures. */
    public function summary(Request $request): JsonResponse
    {
        $period = (string) $request->query('period', today()->format('Y-m'));
        abort_unless((bool) preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $period), 422, 'A period is a month written as YYYY-MM.');
        $from = Carbon::parse("{$period}-01");
        $to = $from->copy()->endOfMonth();
        $scope = $this->scope($request);
        $summary = $this->attendance->summary($from, $to, $scope);

        $employees = Employee::query()->with('department:id,name')
            ->where('status', '!=', Employee::STATUS_EXITED)
            ->when($scope !== null, fn ($q) => $q->whereIn('id', $scope ?: [0]))
            ->orderBy('full_name')->get();

        return response()->json([
            'period' => $period,
            'data' => $employees->map(fn (Employee $e) => [
                'employee' => ['id' => $e->id, 'full_name' => $e->full_name, 'employee_number' => $e->employee_number, 'department' => $e->department?->name],
                ...($summary[$e->id] ?? ['present' => 0, 'late' => 0, 'absent' => 0, 'leave' => 0, 'off' => 0, 'hours' => 0, 'overtime' => 0]),
            ])->values(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'employee_id' => ['required', 'integer', Rule::exists('hr_employees', 'id')->where('company_id', $company)],
            'date' => ['required', 'date', 'before_or_equal:today'],
            'check_in' => ['nullable', 'date_format:H:i'],
            'check_out' => ['nullable', 'date_format:H:i'],
            'status' => ['nullable', Rule::in(Attendance::STATUSES)],
            'note' => ['nullable', 'string', 'max:255'],
        ]);

        $employee = Employee::query()->findOrFail($data['employee_id']);

        if (! $employee->isActive()) {
            throw new RuntimeException("{$employee->full_name} is not an active employee.");
        }

        $record = $this->attendance->record($employee, $data, $request->user());
        app(AuditLogger::class)->log('hr.attendance.recorded', "Recorded {$record->status} for {$employee->full_name} on {$record->date->toDateString()}", $record);

        return response()->json(['message' => 'Attendance saved.', 'data' => $record], 201);
    }

    public function import(Request $request): JsonResponse
    {
        $request->validate(['file' => ['required', 'file', 'mimes:csv,txt', 'max:5120']]);
        $result = $this->attendance->import($request->file('file'), $request->user());

        return response()->json([
            'message' => "{$result['imported']} lines imported".($result['errors'] ? ', '.count($result['errors']).' skipped.' : '.'),
            'data' => $result,
        ]);
    }

    public function shifts(): JsonResponse
    {
        return response()->json(['data' => Shift::query()->orderBy('name')->get()->map(fn (Shift $s) => [...$s->toArray(), 'hours' => $s->hours()])]);
    }

    public function storeShift(Request $request): JsonResponse
    {
        $shift = Shift::create($this->shiftData($request, null));
        $this->defaultOnly($shift);

        return response()->json(['message' => 'Shift saved.', 'data' => $shift], 201);
    }

    public function updateShift(Request $request, Shift $shift): JsonResponse
    {
        $shift->update($this->shiftData($request, $shift));
        $this->defaultOnly($shift);

        return response()->json(['message' => 'Shift saved.', 'data' => $shift]);
    }

    /** @return list<int>|null */
    private function scope(Request $request): ?array
    {
        // The team routes are for department heads: their own people only.
        return $request->routeIs('erp.hr.team.*') ? (HrAccess::teamEmployeeIds($request->user()) ?? null) : null;
    }

    /** @return array<string, mixed> */
    private function shiftData(Request $request, ?Shift $shift): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:60', Rule::unique('hr_shifts', 'name')->where('company_id', $this->tenant->id())->ignore($shift?->id)],
            'start_time' => ['required', 'date_format:H:i'],
            'end_time' => ['required', 'date_format:H:i'],
            'grace_minutes' => ['nullable', 'integer', 'between:0,120'],
            'is_default' => ['sometimes', 'boolean'],
        ]);
    }

    private function defaultOnly(Shift $shift): void
    {
        if ($shift->is_default) {
            Shift::query()->whereKeyNot($shift->id)->update(['is_default' => false]);
        }
    }
}
