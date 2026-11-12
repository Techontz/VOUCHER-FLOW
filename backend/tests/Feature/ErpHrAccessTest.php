<?php

namespace Tests\Feature;

use App\Models\Erp\Hr\PayrollRun;
use App\Models\Erp\Hr\Payslip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Acceptance criterion 13 for HR: people without HR or salary permission see
 * no salary, no disciplinary data, and nothing of another company's.
 */
class ErpHrAccessTest extends TestCase
{
    use ErpHrSupport, RefreshDatabase, TestSupport;

    public function test_salary_is_left_out_of_responses_for_people_without_the_salary_permission(): void
    {
        $hr = $this->setUpHr();
        $id = $this->hire($hr, ['bank_name' => 'CRDB', 'bank_account_number' => '0152-334455'])->assertCreated()->json('data.id');

        // HR manager: sees pay and bank details.
        $this->actingAs($hr['hr'], 'sanctum')->getJson("/api/erp/hr/employees/{$id}")->assertOk()
            ->assertJsonPath('data.contract.basic_salary', 800000)
            ->assertJsonPath('data.bank_account_number', '0152-334455')
            ->assertJsonPath('contracts.0.basic_salary', 800000);

        // A director: may view HR, may not see salaries.
        $director = User::create(['company_id' => $hr['company']->id, 'name' => 'Director', 'email' => 'director@x.test', 'password' => 'x', 'role' => User::ROLE_DIRECTOR, 'status' => 'active']);
        $response = $this->actingAs($director, 'sanctum')->getJson("/api/erp/hr/employees/{$id}")->assertOk();
        $this->assertArrayNotHasKey('basic_salary', $response->json('data.contract'));
        $this->assertArrayNotHasKey('bank_account_number', $response->json('data'));
        $this->assertArrayNotHasKey('basic_salary', $response->json('contracts.0'));
        $this->assertNull($response->json('payslips'));
        $this->assertNull($response->json('discipline'));
        $this->assertStringNotContainsString('800000', $response->getContent());

        $list = $this->actingAs($director, 'sanctum')->getJson('/api/erp/hr/employees')->assertOk();
        $this->assertStringNotContainsString('basic_salary', $list->getContent());

        // Nor may they, or the CEO, write pay.
        $this->actingAs($hr['ceo'], 'sanctum')->postJson("/api/erp/hr/employees/{$id}/contracts", [
            'type' => 'permanent', 'start_date' => now()->toDateString(), 'basic_salary' => 5000000,
        ])->assertForbidden();
    }

    public function test_disciplinary_cases_need_the_discipline_permission(): void
    {
        $hr = $this->setUpHr();
        $id = $this->hire($hr)->json('data.id');

        $case = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/discipline', [
            'employee_id' => $id, 'category' => 'lateness', 'incident_date' => now()->subDays(3)->toDateString(),
            'description' => 'Late four times this month', 'action' => 'verbal_warning',
        ])->assertCreated()->json('data.id');

        $this->actingAs($hr['hr'], 'sanctum')->getJson("/api/erp/hr/employees/{$id}")->assertOk()->assertJsonCount(1, 'discipline');

        foreach (['ceo', 'finance', 'hod', 'employee'] as $who) {
            $this->actingAs($hr[$who], 'sanctum')->getJson('/api/erp/hr/discipline')->assertForbidden();
            $this->actingAs($hr[$who], 'sanctum')->getJson("/api/erp/hr/discipline/{$case}")->assertForbidden();
        }

        $profile = $this->actingAs($hr['ceo'], 'sanctum')->getJson("/api/erp/hr/employees/{$id}")->assertOk();
        $this->assertNull($profile->json('discipline'));
        $this->assertStringNotContainsString('Late four times', $profile->getContent());
    }

    public function test_an_employee_sees_only_their_own_record_and_released_payslips(): void
    {
        $hr = $this->setUpHr();
        $mine = $this->hire($hr, ['full_name' => 'Employee Self', 'user_id' => $hr['employee']->id])->json('data.id');
        $this->hire($hr, ['full_name' => 'Someone Else'], ['type' => 'permanent', 'start_date' => '2025-01-01', 'basic_salary' => 3000000]);

        $this->actingAs($hr['employee'], 'sanctum')->getJson('/api/erp/hr/employees')->assertForbidden();
        $this->actingAs($hr['employee'], 'sanctum')->getJson("/api/erp/hr/employees/{$mine}")->assertForbidden();
        $this->actingAs($hr['employee'], 'sanctum')->getJson('/api/erp/hr/me')->assertOk()
            ->assertJsonPath('data.full_name', 'Employee Self')->assertJsonPath('data.contract.basic_salary', 800000);

        $id = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $this->lastMonth()])->json('data.id');

        // A draft is not yet anybody's payslip.
        $this->actingAs($hr['employee'], 'sanctum')->getJson('/api/erp/hr/me/payslips')->assertOk()->assertJsonCount(0, 'data');

        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/authorise")->assertOk();
        $this->actingAs($hr['finance'], 'sanctum')->postJson("/api/erp/hr/payroll-runs/{$id}/lock")->assertOk();

        $own = Payslip::acrossTenants()->where('payroll_run_id', $id)->where('employee_id', $mine)->value('id');
        $other = Payslip::acrossTenants()->where('payroll_run_id', $id)->where('employee_id', '!=', $mine)->value('id');

        $this->actingAs($hr['employee'], 'sanctum')->getJson('/api/erp/hr/me/payslips')->assertOk()->assertJsonCount(1, 'data');
        $this->actingAs($hr['employee'], 'sanctum')->getJson("/api/erp/hr/me/payslips/{$own}")->assertOk();
        $this->actingAs($hr['employee'], 'sanctum')->getJson("/api/erp/hr/me/payslips/{$other}")->assertNotFound();
        $this->actingAs($hr['employee'], 'sanctum')->get("/api/erp/hr/me/payslips/{$own}/pdf")->assertOk();
    }

    public function test_another_companys_hr_records_are_invisible(): void
    {
        $hr = $this->setUpHr();
        $id = $this->hire($hr)->json('data.id');
        $case = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/discipline', [
            'employee_id' => $id, 'category' => 'misconduct', 'incident_date' => now()->toDateString(), 'description' => 'Something serious',
        ])->json('data.id');

        $other = $this->setUpHr('Bahari Foods');

        $this->actingAs($other['hr'], 'sanctum')->getJson("/api/erp/hr/employees/{$id}")->assertNotFound();
        $this->actingAs($other['hr'], 'sanctum')->putJson("/api/erp/hr/employees/{$id}", ['phone' => '0700'])->assertNotFound();
        $this->actingAs($other['hr'], 'sanctum')->getJson("/api/erp/hr/discipline/{$case}")->assertNotFound();
        $this->actingAs($other['hr'], 'sanctum')->getJson('/api/erp/hr/employees')->assertOk()->assertJsonCount(0, 'data');
        $this->actingAs($other['hr'], 'sanctum')->postJson('/api/erp/hr/discipline', [
            'employee_id' => $id, 'category' => 'misconduct', 'incident_date' => now()->toDateString(), 'description' => 'Cross-tenant attempt',
        ])->assertUnprocessable()->assertJsonValidationErrors('employee_id');
        $this->assertSame(0, PayrollRun::acrossTenants()->where('company_id', $other['company']->id)->count());
    }

    public function test_hr_is_refused_when_the_module_is_off(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'), 'wholesale');
        $company = $erp['company'];
        $company->forceFill(['modules' => array_values(array_diff((array) $company->modules, ['hr']))])->save();

        $this->actingAs($erp['admin'], 'sanctum')->getJson('/api/erp/hr/overview')->assertForbidden()->assertJsonPath('code', 'module_disabled');
    }

    public function test_every_role_gets_self_service_and_only_hr_roles_get_more(): void
    {
        $hr = $this->setUpHr();

        foreach ([User::ROLE_EMPLOYEE, User::ROLE_DRIVER, User::ROLE_STOREKEEPER, User::ROLE_CASHIER] as $role) {
            $user = User::create(['company_id' => $hr['company']->id, 'name' => $role, 'email' => "{$role}@x.test", 'password' => 'x', 'role' => $role, 'status' => 'active']);
            $this->assertTrue($user->hasPermission('hr.self'), $role);
            $this->assertFalse($user->hasPermission('hr.salary'), $role);
        }

        $this->assertFalse($hr['hr']->hasPermission('hr.payroll.authorise'));
        $this->assertTrue($hr['finance']->hasPermission('hr.payroll.authorise'));
        $this->assertTrue($hr['hod']->hasPermission('hr.leave.approve'));
        $this->assertFalse($hr['hod']->hasPermission('hr.view'));
    }

    public function test_every_hr_screen_endpoint_answers(): void
    {
        $hr = $this->setUpHr();
        $id = $this->hire($hr, ['user_id' => $hr['admin']->id])->json('data.id');
        $run = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/payroll-runs', ['period' => $this->lastMonth()])->json('data.id');
        $loan = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/loans', [
            'employee_id' => $id, 'type' => 'advance', 'principal' => 100000, 'installment' => 50000, 'start_period' => now()->format('Y-m'), 'issued_on' => now()->toDateString(),
        ])->json('data.id');
        $period = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/appraisal-periods', ['name' => '2026 review', 'start_date' => now()->startOfYear()->toDateString(), 'end_date' => now()->endOfYear()->toDateString()])->assertCreated()->json('data.id');
        $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/appraisals', ['period_id' => $period])->assertCreated();

        foreach ([
            'overview', 'settings', 'lookups', 'employees', "employees/{$id}", 'attendance', 'attendance/summary', 'shifts',
            'leave/balances', 'leave/requests', 'leave/calendar', 'leave-types', 'appraisal-periods', 'appraisals', 'trainings', 'exits',
            'vacancies', 'payroll-runs', "payroll-runs/{$run}", 'statutory-returns', 'statutory-rates', 'payment-accounts',
            'loans', "loans/{$loan}", 'pay-items', 'discipline', 'me', 'me/payslips', 'me/leave', 'me/attendance', 'me/appraisals',
            'linkable-users',
        ] as $path) {
            $this->actingAs($hr['admin'], 'sanctum')->getJson("/api/erp/hr/{$path}")->assertOk();
        }

        $this->actingAs($hr['hod'], 'sanctum')->getJson('/api/erp/hr/team/attendance')->assertOk();
        $this->actingAs($hr['hod'], 'sanctum')->getJson('/api/erp/hr/team/attendance/summary')->assertOk();
        $this->actingAs($hr['hod'], 'sanctum')->getJson('/api/erp/hr/attendance')->assertForbidden();
    }
}
