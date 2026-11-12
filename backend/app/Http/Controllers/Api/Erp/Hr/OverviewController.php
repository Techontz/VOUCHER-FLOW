<?php

namespace App\Http\Controllers\Api\Erp\Hr;

use App\Http\Controllers\Controller;
use App\Models\Department;
use App\Models\Erp\Hr\Applicant;
use App\Models\Erp\Hr\Attendance;
use App\Models\Erp\Hr\Contract;
use App\Models\Erp\Hr\DisciplineCase;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\HrSetting;
use App\Models\Erp\Hr\LeaveRequest;
use App\Models\Erp\Hr\PayrollRun;
use App\Models\Erp\Hr\Separation;
use App\Models\Erp\Hr\Shift;
use App\Models\Erp\Hr\Vacancy;
use App\Services\AuditLogger;
use App\Services\Erp\Hr\HrAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** The HR dashboard, HR settings and the small lists HR forms pick from. */
class OverviewController extends Controller
{
    public function overview(Request $request): JsonResponse
    {
        $user = $request->user();
        $today = today();

        $byDepartment = Employee::query()->where('status', Employee::STATUS_ACTIVE)
            ->selectRaw('department_id, count(*) as headcount')->groupBy('department_id')->get();
        $names = Department::query()->whereIn('id', $byDepartment->pluck('department_id')->filter())->pluck('name', 'id');

        $onLeave = LeaveRequest::query()->with('employee:id,full_name,employee_number,department_id', 'leaveType:id,name,code')
            ->where('status', LeaveRequest::STATUS_APPROVED)
            ->whereDate('start_date', '<=', $today)->whereDate('end_date', '>=', $today)
            ->get();

        $team = HrAccess::teamEmployeeIds($user);
        $pendingLeave = LeaveRequest::query()->where('status', LeaveRequest::STATUS_PENDING)
            ->when($team !== null, fn ($q) => $q->whereIn('employee_id', $team ?: [0]))->count();

        $latestRun = PayrollRun::query()->latest('period')->first();
        $currentRun = PayrollRun::query()->where('period', $today->format('Y-m'))->first();
        $payrollFigures = HrAccess::worksOnPayroll($user) || HrAccess::seesSalary($user);

        $expiring = Contract::query()->with('employee:id,full_name,employee_number,status')
            ->where('status', Contract::STATUS_ACTIVE)->whereNotNull('end_date')
            ->whereDate('end_date', '>=', $today)->whereDate('end_date', '<=', $today->copy()->addDays(60))
            ->whereHas('employee', fn ($q) => $q->where('status', '!=', Employee::STATUS_EXITED))
            ->orderBy('end_date')->get();

        $probation = Employee::query()->where('status', Employee::STATUS_ACTIVE)
            ->whereDate('probation_end', '>=', $today)->whereDate('probation_end', '<=', $today->copy()->addDays(30))
            ->orderBy('probation_end')->get(['id', 'full_name', 'employee_number', 'probation_end']);

        $attendance = Attendance::query()->whereDate('date', $today)
            ->selectRaw('status, count(*) as n')->groupBy('status')->pluck('n', 'status');

        return response()->json(['data' => [
            'headcount' => Employee::query()->where('status', Employee::STATUS_ACTIVE)->count(),
            'suspended' => Employee::query()->where('status', Employee::STATUS_SUSPENDED)->count(),
            'by_department' => $byDepartment->map(fn ($r) => [
                'department_id' => $r->department_id,
                'department' => $names[$r->department_id] ?? null,
                'headcount' => (int) $r->headcount,
            ])->sortByDesc('headcount')->values(),
            'on_leave_today' => $onLeave->map(fn ($r) => [
                'id' => $r->id, 'employee' => $r->employee?->full_name, 'employee_id' => $r->employee_id,
                'leave_type' => $r->leaveType?->name, 'end_date' => $r->end_date->toDateString(),
            ])->values(),
            'pending_leave' => $pendingLeave,
            'attendance_today' => [
                'present' => (int) ($attendance['present'] ?? 0), 'late' => (int) ($attendance['late'] ?? 0),
                'absent' => (int) ($attendance['absent'] ?? 0), 'leave' => (int) ($attendance['leave'] ?? 0),
            ],
            'payroll' => [
                'current_period' => $today->format('Y-m'),
                'current' => $currentRun ? $this->runSummary($currentRun, $payrollFigures) : null,
                'latest' => $latestRun ? $this->runSummary($latestRun, $payrollFigures) : null,
            ],
            'contracts_expiring' => $expiring->map(fn ($c) => [
                'contract_id' => $c->id, 'employee_id' => $c->employee_id, 'employee' => $c->employee?->full_name,
                'type' => $c->type, 'end_date' => $c->end_date->toDateString(),
            ])->values(),
            'probation_ending' => $probation->map(fn ($e) => [
                'employee_id' => $e->id, 'employee' => $e->full_name, 'probation_end' => $e->probation_end->toDateString(),
            ])->values(),
            'open_vacancies' => Vacancy::query()->where('status', 'open')->count(),
            'applicants_in_pipeline' => Applicant::query()->whereIn('stage', ['applied', 'screening', 'interview', 'offer'])->count(),
            'exits_in_progress' => Separation::query()->where('status', 'in_progress')->count(),
            'open_discipline_cases' => HrAccess::seesDiscipline($user) ? DisciplineCase::query()->where('status', 'open')->count() : null,
        ]]);
    }

    public function settings(): JsonResponse
    {
        return response()->json(['data' => HrSetting::current()]);
    }

    public function updateSettings(Request $request, AuditLogger $audit): JsonResponse
    {
        $data = $request->validate([
            'country' => ['sometimes', 'string', 'size:2'],
            'sdl_exempt' => ['sometimes', 'boolean'],
            'deduct_absence' => ['sometimes', 'boolean'],
            'working_days_per_month' => ['sometimes', 'numeric', 'between:1,31'],
            'hours_per_day' => ['sometimes', 'numeric', 'between:1,24'],
            'overtime_multiplier' => ['sometimes', 'numeric', 'between:1,5'],
        ]);

        $settings = HrSetting::current();
        $before = $settings->only(array_keys($data));
        $settings->update($data);
        $audit->log('hr.settings.updated', 'Updated HR and payroll settings', $settings, $before, $settings->only(array_keys($data)));

        return response()->json(['message' => 'Settings saved.', 'data' => $settings]);
    }

    /** Departments, shifts and active people, for the pickers on HR forms. */
    public function lookups(): JsonResponse
    {
        return response()->json(['data' => [
            'departments' => Department::query()->where('is_active', true)->orderBy('name')->get(['id', 'name', 'hod_user_id', 'manager_user_id']),
            'shifts' => Shift::query()->orderBy('name')->get(),
            'employees' => Employee::query()->where('status', '!=', Employee::STATUS_EXITED)->orderBy('full_name')
                ->get(['id', 'full_name', 'employee_number', 'department_id', 'job_title', 'user_id']),
        ]]);
    }

    /** @return array<string, mixed> */
    private function runSummary(PayrollRun $run, bool $figures): array
    {
        return [
            'id' => $run->id, 'number' => $run->number, 'period' => $run->period, 'status' => $run->status,
            'employees_count' => $run->employees_count,
            'net' => $figures ? (float) $run->net : null,
            'gross' => $figures ? (float) $run->gross : null,
        ];
    }
}
