<?php

namespace App\Http\Controllers\Api\Erp\Hr;

use App\Http\Controllers\Controller;
use App\Models\Erp\Hr\Appraisal;
use App\Models\Erp\Hr\Attendance;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\LeaveRequest;
use App\Models\Erp\Hr\Payslip;
use App\Services\Erp\Hr\HrAccess;
use App\Services\Erp\Hr\LeaveService;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * My HR: a person's own record, payslips, leave and attendance. Everything
 * here is found through the caller's own employee record, so nobody can
 * reach anyone else's by changing an id: another person's payslip is a 404.
 */
class SelfServiceController extends Controller
{
    public function __construct(private readonly LeaveService $leave, private readonly TenantContext $tenant) {}

    public function me(Request $request): JsonResponse
    {
        $employee = $this->employee($request);
        $employee->load('department:id,name', 'manager:id,full_name', 'shift', 'activeContract');
        $contract = $employee->activeContract;

        return response()->json(['data' => [
            ...$employee->only([
                'id', 'employee_number', 'full_name', 'email', 'phone', 'national_id', 'tin', 'nssf_number', 'gender', 'address',
                'next_of_kin_name', 'next_of_kin_phone', 'next_of_kin_relation', 'employment_type', 'job_title', 'grade',
                'status', 'bank_name', 'bank_account_number', 'heslb_beneficiary',
            ]),
            'date_of_birth' => $employee->date_of_birth?->toDateString(),
            'hire_date' => $employee->hire_date?->toDateString(),
            'probation_end' => $employee->probation_end?->toDateString(),
            'department' => $employee->department?->name,
            'manager' => $employee->manager?->full_name,
            'shift' => $employee->shift?->only(['name', 'start_time', 'end_time']),
            // Their own pay is theirs to see.
            'contract' => $contract ? [
                'type' => $contract->type, 'start_date' => $contract->start_date->toDateString(), 'end_date' => $contract->end_date?->toDateString(),
                'basic_salary' => (float) $contract->basic_salary, 'housing_allowance' => (float) $contract->housing_allowance,
                'transport_allowance' => (float) $contract->transport_allowance, 'other_allowance' => (float) $contract->other_allowance,
            ] : null,
            'leave_balances' => $this->leave->balancesFor($employee, (int) $request->query('year', now()->year)),
        ]]);
    }

    /** People may correct their own contact details and next of kin; the rest is HR's. */
    public function update(Request $request): JsonResponse
    {
        $employee = $this->employee($request);
        $employee->update($request->validate([
            'phone' => ['nullable', 'string', 'max:40'],
            'address' => ['nullable', 'string', 'max:255'],
            'next_of_kin_name' => ['nullable', 'string', 'max:160'],
            'next_of_kin_phone' => ['nullable', 'string', 'max:40'],
            'next_of_kin_relation' => ['nullable', 'string', 'max:60'],
        ]));

        return response()->json(['message' => 'Your details are saved.']);
    }

    public function payslips(Request $request): JsonResponse
    {
        $employee = $this->employee($request);

        return response()->json(['data' => $this->releasedPayslips($employee)
            ->with('run:id,number,period,status,payment_date')->latest('id')
            ->get(['id', 'payroll_run_id', 'gross', 'total_deductions', 'net'])]);
    }

    public function payslip(Request $request, int $payslip): JsonResponse
    {
        $slip = $this->releasedPayslips($this->employee($request))->findOrFail($payslip);

        return response()->json(['data' => PayrollController::presentPayslip($slip)]);
    }

    public function payslipPdf(Request $request, int $payslip): Response
    {
        return PayrollController::pdf($this->releasedPayslips($this->employee($request))->findOrFail($payslip));
    }

    public function leave(Request $request): JsonResponse
    {
        $employee = $this->employee($request);

        return response()->json([
            'data' => LeaveRequest::query()->with('leaveType:id,name,code', 'decider:id,name')
                ->where('employee_id', $employee->id)->latest('start_date')->get(),
            'balances' => $this->leave->balancesFor($employee, (int) $request->query('year', now()->year)),
        ]);
    }

    public function requestLeave(Request $request): JsonResponse
    {
        $employee = $this->employee($request);
        $data = $request->validate([
            'leave_type_id' => ['required', 'integer', Rule::exists('hr_leave_types', 'id')->where('company_id', $this->tenant->id())],
            'start_date' => ['required', 'date'],
            'end_date' => ['required', 'date'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        return response()->json(['message' => 'Leave requested.', 'data' => $this->leave->request($employee, $data, $request->user())], 201);
    }

    public function cancelLeave(Request $request, int $leaveRequest): JsonResponse
    {
        $employee = $this->employee($request);
        $row = LeaveRequest::query()->where('employee_id', $employee->id)->findOrFail($leaveRequest);

        return response()->json(['message' => 'Leave cancelled.', 'data' => $this->leave->cancel($row, $request->user())]);
    }

    public function attendance(Request $request): JsonResponse
    {
        $employee = $this->employee($request);
        $month = (string) $request->query('month', today()->format('Y-m'));
        abort_unless((bool) preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $month), 422, 'A month is written as YYYY-MM.');
        $from = Carbon::parse("{$month}-01");

        return response()->json([
            'month' => $month,
            'data' => Attendance::query()->where('employee_id', $employee->id)
                ->whereDate('date', '>=', $from)->whereDate('date', '<=', $from->copy()->endOfMonth())->orderBy('date')->get(),
        ]);
    }

    public function appraisals(Request $request): JsonResponse
    {
        $employee = $this->employee($request);

        return response()->json(['data' => Appraisal::query()->with('period:id,name', 'reviewer:id,name', 'objectives')
            ->where('employee_id', $employee->id)->latest('id')->get()]);
    }

    public function commentAppraisal(Request $request, int $appraisal): JsonResponse
    {
        $row = Appraisal::query()->where('employee_id', $this->employee($request)->id)->findOrFail($appraisal);

        if ($row->status === 'completed') {
            throw new RuntimeException('This appraisal is complete and cannot change.');
        }

        $row->update($request->validate(['employee_comments' => ['required', 'string', 'max:5000']]));

        return response()->json(['message' => 'Your comments are saved.', 'data' => $row]);
    }

    private function employee(Request $request): Employee
    {
        return HrAccess::employeeFor($request->user())
            ?? abort(404, 'You do not have an employee record yet. Ask HR to add you.');
    }

    private function releasedPayslips(Employee $employee)
    {
        return Payslip::query()->where('employee_id', $employee->id)
            ->whereHas('run', fn ($q) => $q->whereIn('status', ['locked', 'posted', 'paid']));
    }
}
