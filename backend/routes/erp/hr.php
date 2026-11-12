<?php

use App\Http\Controllers\Api\Erp\Hr\AttendanceController;
use App\Http\Controllers\Api\Erp\Hr\DisciplineController;
use App\Http\Controllers\Api\Erp\Hr\EmployeeController;
use App\Http\Controllers\Api\Erp\Hr\LeaveController;
use App\Http\Controllers\Api\Erp\Hr\LoanController;
use App\Http\Controllers\Api\Erp\Hr\OverviewController;
use App\Http\Controllers\Api\Erp\Hr\PayrollController;
use App\Http\Controllers\Api\Erp\Hr\PerformanceController;
use App\Http\Controllers\Api\Erp\Hr\RecruitmentController;
use App\Http\Controllers\Api\Erp\Hr\SelfServiceController;
use App\Http\Controllers\Api\Erp\Hr\SeparationController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| HR Flow & payroll, under /api/erp/hr
|--------------------------------------------------------------------------
| Salary and discipline are field-level on top of these gates: the API
| resources leave pay out for anyone without hr.salary, and disciplinary
| cases have routes of their own behind hr.discipline.
*/

Route::prefix('hr')->middleware('module:hr')->group(function () {
    Route::middleware('permission:hr.view')->group(function () {
        Route::get('overview', [OverviewController::class, 'overview']);
        Route::get('settings', [OverviewController::class, 'settings']);
        Route::get('lookups', [OverviewController::class, 'lookups']);
        Route::get('employees', [EmployeeController::class, 'index']);
        Route::get('employees/{employee}', [EmployeeController::class, 'show']);
        Route::get('attendance', [AttendanceController::class, 'daily']);
        Route::get('attendance/summary', [AttendanceController::class, 'summary']);
        Route::get('shifts', [AttendanceController::class, 'shifts']);
        Route::get('leave/balances', [LeaveController::class, 'balances']);
        Route::get('appraisal-periods', [PerformanceController::class, 'periods']);
        Route::get('appraisals', [PerformanceController::class, 'index']);
        Route::get('appraisals/{appraisal}', [PerformanceController::class, 'show']);
        Route::get('trainings', [PerformanceController::class, 'trainings']);
        Route::get('exits', [SeparationController::class, 'index']);
        Route::get('exits/{separation}', [SeparationController::class, 'show']);
    });

    Route::middleware('permission:hr.manage')->group(function () {
        Route::put('settings', [OverviewController::class, 'updateSettings']);
        Route::get('linkable-users', [EmployeeController::class, 'linkableUsers']);
        Route::post('employees', [EmployeeController::class, 'store']);
        Route::put('employees/{employee}', [EmployeeController::class, 'update']);
        Route::post('employees/{employee}/movements', [EmployeeController::class, 'storeMovement']);
        Route::post('leave-types', [LeaveController::class, 'storeType']);
        Route::put('leave-types/{leaveType}', [LeaveController::class, 'updateType']);
        Route::post('leave/requests', [LeaveController::class, 'store']);
        Route::put('leave/balances/{leaveBalance}', [LeaveController::class, 'adjustBalance']);
        Route::post('appraisal-periods', [PerformanceController::class, 'storePeriod']);
        Route::put('appraisal-periods/{appraisalPeriod}', [PerformanceController::class, 'updatePeriod']);
        Route::post('appraisals', [PerformanceController::class, 'store']);
        Route::put('appraisals/{appraisal}', [PerformanceController::class, 'update']);
        Route::post('appraisals/{appraisal}/complete', [PerformanceController::class, 'complete']);
        Route::post('appraisals/{appraisal}/objectives', [PerformanceController::class, 'storeObjective']);
        Route::put('appraisal-objectives/{objective}', [PerformanceController::class, 'updateObjective']);
        Route::delete('appraisal-objectives/{objective}', [PerformanceController::class, 'destroyObjective']);
        Route::post('trainings', [PerformanceController::class, 'storeTraining']);
        Route::put('trainings/{training}', [PerformanceController::class, 'updateTraining']);
        Route::post('exits', [SeparationController::class, 'store']);
        Route::put('exits/{separation}', [SeparationController::class, 'update']);
        Route::post('exits/{separation}/items/{item}', [SeparationController::class, 'clear']);
        Route::post('exits/{separation}/complete', [SeparationController::class, 'complete']);
    });

    // A new contract carries pay: it needs hr.salary here and hr.manage in the controller.
    Route::post('employees/{employee}/contracts', [EmployeeController::class, 'storeContract'])->middleware('permission:hr.salary');

    Route::middleware('permission:hr.attendance')->group(function () {
        Route::post('attendance', [AttendanceController::class, 'store']);
        Route::post('attendance/import', [AttendanceController::class, 'import']);
        Route::post('shifts', [AttendanceController::class, 'storeShift']);
        Route::put('shifts/{shift}', [AttendanceController::class, 'updateShift']);
    });

    // Department heads: their own team only.
    Route::middleware('permission:hr.leave.approve')->group(function () {
        Route::get('team/attendance', [AttendanceController::class, 'daily'])->name('erp.hr.team.attendance');
        Route::get('team/attendance/summary', [AttendanceController::class, 'summary'])->name('erp.hr.team.summary');
        Route::post('leave/requests/{leaveRequest}/approve', [LeaveController::class, 'approve']);
        Route::post('leave/requests/{leaveRequest}/reject', [LeaveController::class, 'reject']);
    });

    // HR sees every request, an approver their team; the controller decides.
    Route::get('leave/requests', [LeaveController::class, 'index']);
    Route::get('leave/calendar', [LeaveController::class, 'calendar']);
    Route::post('leave/requests/{leaveRequest}/cancel', [LeaveController::class, 'cancel']);
    Route::get('leave-types', [LeaveController::class, 'types'])->middleware('permission:hr.self');

    Route::middleware('permission:hr.recruit')->group(function () {
        Route::get('vacancies', [RecruitmentController::class, 'index']);
        Route::get('vacancies/{vacancy}', [RecruitmentController::class, 'show']);
        Route::post('vacancies', [RecruitmentController::class, 'store']);
        Route::put('vacancies/{vacancy}', [RecruitmentController::class, 'update']);
        Route::post('vacancies/{vacancy}/applicants', [RecruitmentController::class, 'storeApplicant']);
        Route::put('applicants/{applicant}', [RecruitmentController::class, 'updateApplicant']);
        Route::post('applicants/{applicant}/hire', [RecruitmentController::class, 'hire']);
        Route::post('employees/{employee}/onboarding', [EmployeeController::class, 'storeTask']);
        Route::put('onboarding/{task}', [EmployeeController::class, 'updateTask']);
    });

    // Reading payroll needs any payroll permission (checked in the controllers).
    Route::get('payroll-runs', [PayrollController::class, 'index']);
    Route::get('payroll-runs/{payrollRun}', [PayrollController::class, 'show']);
    Route::get('payslips/{payslip}', [PayrollController::class, 'payslip']);
    Route::get('payslips/{payslip}/pdf', [PayrollController::class, 'payslipPdf']);
    Route::get('statutory-returns', [PayrollController::class, 'statutory']);
    Route::get('statutory-rates', [PayrollController::class, 'rates']);
    Route::get('payment-accounts', [PayrollController::class, 'paymentAccounts']);
    Route::get('loans', [LoanController::class, 'index']);
    Route::get('loans/{loan}', [LoanController::class, 'show']);
    Route::get('pay-items', [LoanController::class, 'items']);

    Route::middleware('permission:hr.payroll.prepare')->group(function () {
        Route::post('payroll-runs', [PayrollController::class, 'store']);
        Route::post('payroll-runs/{payrollRun}/recalculate', [PayrollController::class, 'recalculate']);
        Route::delete('payroll-runs/{payrollRun}', [PayrollController::class, 'destroy']);
        Route::post('statutory-rates', [PayrollController::class, 'storeRate']);
        Route::post('loans', [LoanController::class, 'store']);
        Route::post('loans/{loan}/cancel', [LoanController::class, 'cancel']);
        Route::post('pay-items', [LoanController::class, 'storeItem']);
        Route::put('pay-items/{payItem}', [LoanController::class, 'updateItem']);
    });

    Route::middleware('permission:hr.payroll.authorise')->group(function () {
        Route::post('payroll-runs/{payrollRun}/authorise', [PayrollController::class, 'authorise']);
        Route::post('payroll-runs/{payrollRun}/return', [PayrollController::class, 'returnToDraft']);
        Route::post('payroll-runs/{payrollRun}/lock', [PayrollController::class, 'lock']);
    });

    Route::middleware('permission:hr.payroll.post')->group(function () {
        Route::post('payroll-runs/{payrollRun}/post', [PayrollController::class, 'post']);
        Route::post('payroll-runs/{payrollRun}/pay', [PayrollController::class, 'pay']);
    });

    Route::middleware('permission:hr.discipline')->group(function () {
        Route::get('discipline', [DisciplineController::class, 'index']);
        Route::get('discipline/{disciplineCase}', [DisciplineController::class, 'show']);
        Route::post('discipline', [DisciplineController::class, 'store']);
        Route::put('discipline/{disciplineCase}', [DisciplineController::class, 'update']);
        Route::post('discipline/{disciplineCase}/close', [DisciplineController::class, 'close']);
    });

    Route::prefix('me')->middleware('permission:hr.self')->group(function () {
        Route::get('/', [SelfServiceController::class, 'me']);
        Route::put('/', [SelfServiceController::class, 'update']);
        Route::get('payslips', [SelfServiceController::class, 'payslips']);
        Route::get('payslips/{payslip}', [SelfServiceController::class, 'payslip'])->whereNumber('payslip');
        Route::get('payslips/{payslip}/pdf', [SelfServiceController::class, 'payslipPdf'])->whereNumber('payslip');
        Route::get('leave', [SelfServiceController::class, 'leave']);
        Route::post('leave', [SelfServiceController::class, 'requestLeave']);
        Route::post('leave/{leaveRequest}/cancel', [SelfServiceController::class, 'cancelLeave'])->whereNumber('leaveRequest');
        Route::get('attendance', [SelfServiceController::class, 'attendance']);
        Route::get('appraisals', [SelfServiceController::class, 'appraisals']);
        Route::put('appraisals/{appraisal}', [SelfServiceController::class, 'commentAppraisal'])->whereNumber('appraisal');
    });
});
