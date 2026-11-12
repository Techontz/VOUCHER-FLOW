<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\Erp\Hr\Attendance;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\LeaveType;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Leave balances move only on approval and come back on cancellation;
 * approvers act for their own department; attendance imports from a
 * biometric CSV; recruitment, onboarding and exits complete their flows.
 */
class ErpHrLeaveTest extends TestCase
{
    use ErpHrSupport, RefreshDatabase, TestSupport;

    private function type(array $hr, string $code): int
    {
        $this->actingAs($hr['hr'], 'sanctum')->getJson('/api/erp/hr/leave-types')->assertOk();

        return (int) LeaveType::acrossTenants()->where('company_id', $hr['company']->id)->where('code', $code)->value('id');
    }

    /** @return array{0: string, 1: string} Monday and Tuesday of a week ahead, in this year */
    private function workingDays(int $count = 2): array
    {
        $monday = now()->next(Carbon::MONDAY);
        if ($monday->year !== now()->year) {
            $monday = now()->startOfYear()->next(Carbon::MONDAY)->addYear();
        }

        return [$monday->toDateString(), $monday->copy()->addDays($count - 1)->toDateString()];
    }

    private function balance(array $hr, User $who, string $code): array
    {
        return collect($this->actingAs($who, 'sanctum')->getJson('/api/erp/hr/me/leave')->assertOk()->json('balances'))
            ->firstWhere('leave_type.code', $code);
    }

    public function test_leave_balance_arithmetic_through_request_approval_and_cancellation(): void
    {
        $hr = $this->setUpHr();
        $this->hire($hr, ['full_name' => 'Employee Self', 'user_id' => $hr['employee']->id]);
        $type = $this->type($hr, 'compassionate');
        [$from, $to] = $this->workingDays(2);

        $this->assertEquals(4, $this->balance($hr, $hr['employee'], 'compassionate')['available']);

        $request = $this->actingAs($hr['employee'], 'sanctum')->postJson('/api/erp/hr/me/leave', [
            'leave_type_id' => $type, 'start_date' => $from, 'end_date' => $to, 'reason' => 'Funeral in Moshi',
        ])->assertCreated()->assertJsonPath('data.days', '2.00')->json('data.id');

        $this->assertEquals(4, $this->balance($hr, $hr['employee'], 'compassionate')['available'], 'Pending leave takes nothing yet.');

        // The employee cannot approve their own; the HOD of their department can.
        $this->actingAs($hr['employee'], 'sanctum')->postJson("/api/erp/hr/leave/requests/{$request}/approve")->assertForbidden();
        $this->actingAs($hr['hod'], 'sanctum')->postJson("/api/erp/hr/leave/requests/{$request}/approve")->assertOk()->assertJsonPath('data.status', 'approved');
        $this->actingAs($hr['hod'], 'sanctum')->postJson("/api/erp/hr/leave/requests/{$request}/approve")->assertStatus(422);

        $balance = $this->balance($hr, $hr['employee'], 'compassionate');
        $this->assertEquals(2, $balance['taken']);
        $this->assertEquals(2, $balance['available']);

        // Three more days than remain are refused.
        [$later] = [now()->next(Carbon::MONDAY)->addWeeks(2)->toDateString()];
        $this->actingAs($hr['employee'], 'sanctum')->postJson('/api/erp/hr/me/leave', [
            'leave_type_id' => $type, 'start_date' => $later, 'end_date' => Carbon::parse($later)->addDays(2)->toDateString(),
        ])->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'Only 2'));

        // Overlapping dates are refused.
        $this->actingAs($hr['employee'], 'sanctum')->postJson('/api/erp/hr/me/leave', [
            'leave_type_id' => $type, 'start_date' => $from, 'end_date' => $from,
        ])->assertStatus(422);

        // Cancelling before it starts gives the days back.
        $this->actingAs($hr['employee'], 'sanctum')->postJson("/api/erp/hr/me/leave/{$request}/cancel")->assertOk()->assertJsonPath('data.status', 'cancelled');
        $balance = $this->balance($hr, $hr['employee'], 'compassionate');
        $this->assertEquals(0, $balance['taken']);
        $this->assertEquals(4, $balance['available']);
    }

    public function test_annual_leave_accrues_month_by_month(): void
    {
        $hr = $this->setUpHr();
        $this->hire($hr, ['full_name' => 'Employee Self', 'user_id' => $hr['employee']->id, 'hire_date' => '2024-03-01']);

        $annual = $this->balance($hr, $hr['employee'], 'annual');
        $this->assertEquals(28, $annual['entitled']);
        $this->assertEquals(round(28 * now()->month / 12, 2), $annual['accrued']);
        $this->assertEquals(round(28 * now()->month / 12, 2), $annual['available']);
    }

    public function test_a_head_of_another_department_cannot_decide(): void
    {
        $hr = $this->setUpHr();
        $this->hire($hr, ['full_name' => 'Employee Self', 'user_id' => $hr['employee']->id]);
        $type = $this->type($hr, 'sick');
        [$from, $to] = $this->workingDays(1);

        $request = $this->actingAs($hr['employee'], 'sanctum')->postJson('/api/erp/hr/me/leave', [
            'leave_type_id' => $type, 'start_date' => $from, 'end_date' => $to,
        ])->assertCreated()->json('data.id');

        $otherHod = app(TenantContext::class)->forCompany($hr['company'], function () use ($hr) {
            $user = User::create(['company_id' => $hr['company']->id, 'name' => 'Other HOD', 'email' => 'otherhod@x.test', 'password' => 'x', 'role' => User::ROLE_HOD, 'status' => 'active']);
            Department::create(['company_id' => $hr['company']->id, 'name' => 'Sales', 'hod_user_id' => $user->id]);

            return $user;
        });

        $this->actingAs($otherHod, 'sanctum')->postJson("/api/erp/hr/leave/requests/{$request}/approve")->assertForbidden();
        $this->actingAs($otherHod, 'sanctum')->getJson('/api/erp/hr/leave/requests')->assertOk()->assertJsonCount(0, 'data');
        $this->actingAs($hr['hod'], 'sanctum')->getJson('/api/erp/hr/leave/requests')->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.can_decide', true);
        $this->actingAs($hr['hod'], 'sanctum')->postJson("/api/erp/hr/leave/requests/{$request}/reject", ['note' => 'Busy week'])->assertOk()->assertJsonPath('data.status', 'rejected');
    }

    public function test_attendance_imports_from_a_biometric_csv_and_reports_bad_lines(): void
    {
        $hr = $this->setUpHr();
        $this->hire($hr, ['employee_number' => 'WC-0001']);
        $this->hire($hr, ['employee_number' => 'WC-0002', 'full_name' => 'Baraka Mollel']);
        $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/shifts', ['name' => 'Day', 'start_time' => '08:00', 'end_time' => '17:00', 'grace_minutes' => 10, 'is_default' => true])->assertCreated();

        $day = now()->subDays(3)->toDateString();
        $csv = "employee_number,date,time_in,time_out\nWC-0001,{$day},08:00,19:00\nWC-0002,{$day},08:40,17:00\nWC-9999,{$day},08:00,17:00\nWC-0001,not-a-date,08:00,17:00\n";
        $file = UploadedFile::fake()->createWithContent('biometric.csv', $csv);

        $this->actingAs($hr['hr'], 'sanctum')->post('/api/erp/hr/attendance/import', ['file' => $file], ['Accept' => 'application/json'])
            ->assertOk()->assertJsonPath('data.imported', 2)->assertJsonCount(2, 'data.errors')
            ->assertJsonPath('data.errors.0.line', 4);

        $rows = Attendance::acrossTenants()->whereDate('date', $day)->get()->keyBy(fn ($a) => Employee::acrossTenants()->find($a->employee_id)->employee_number);
        $this->assertSame('present', $rows['WC-0001']->status);
        $this->assertEquals(2, (float) $rows['WC-0001']->overtime_hours);
        $this->assertSame('late', $rows['WC-0002']->status);

        $this->actingAs($hr['employee'], 'sanctum')->post('/api/erp/hr/attendance/import', ['file' => $file], ['Accept' => 'application/json'])->assertForbidden();
    }

    public function test_an_applicant_is_hired_into_an_employee_with_onboarding(): void
    {
        $hr = $this->setUpHr();
        $vacancy = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/vacancies', [
            'title' => 'Quality controller', 'department_id' => $hr['department']->id, 'positions' => 1, 'employment_type' => 'permanent',
        ])->assertCreated()->json('data.id');
        $applicant = $this->actingAs($hr['hr'], 'sanctum')->postJson("/api/erp/hr/vacancies/{$vacancy}/applicants", ['name' => 'Zawadi Kimaro', 'phone' => '0754000111'])->json('data.id');
        $this->actingAs($hr['hr'], 'sanctum')->putJson("/api/erp/hr/applicants/{$applicant}", ['stage' => 'offer'])->assertOk();

        $employee = $this->actingAs($hr['hr'], 'sanctum')->postJson("/api/erp/hr/applicants/{$applicant}/hire", [
            'hire_date' => now()->toDateString(),
            'contract' => ['type' => 'probation', 'start_date' => now()->toDateString(), 'basic_salary' => 650000],
        ])->assertCreated()->assertJsonPath('data.job_title', 'Quality controller')->json('data.id');

        $this->actingAs($hr['hr'], 'sanctum')->getJson("/api/erp/hr/vacancies/{$vacancy}")->assertJsonPath('data.status', 'filled');
        $this->actingAs($hr['hr'], 'sanctum')->postJson("/api/erp/hr/applicants/{$applicant}/hire", ['hire_date' => now()->toDateString()])->assertStatus(422);
        $profile = $this->actingAs($hr['hr'], 'sanctum')->getJson("/api/erp/hr/employees/{$employee}")->assertOk();
        $this->assertGreaterThan(3, count($profile->json('onboarding')));
    }

    public function test_an_exit_completes_only_after_clearance_and_ends_employment(): void
    {
        $hr = $this->setUpHr();
        $id = $this->hire($hr, ['user_id' => $hr['employee']->id])->json('data.id');

        $exit = $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/exits', [
            'employee_id' => $id, 'type' => 'resignation', 'notice_date' => now()->toDateString(), 'last_working_day' => now()->addDays(30)->toDateString(),
        ])->assertCreated()->json('data');

        $this->assertGreaterThan(0, $exit['final_dues']);
        $this->actingAs($hr['ceo'], 'sanctum')->getJson("/api/erp/hr/exits/{$exit['id']}")->assertOk()->assertJsonMissingPath('data.final_dues');

        $this->actingAs($hr['hr'], 'sanctum')->postJson("/api/erp/hr/exits/{$exit['id']}/complete")->assertStatus(422);

        foreach ($exit['items'] as $item) {
            $this->actingAs($hr['hr'], 'sanctum')->postJson("/api/erp/hr/exits/{$exit['id']}/items/{$item['id']}", ['cleared' => true])->assertOk();
        }

        $this->actingAs($hr['hr'], 'sanctum')->postJson("/api/erp/hr/exits/{$exit['id']}/complete")->assertOk()->assertJsonPath('data.status', 'completed');
        $this->actingAs($hr['hr'], 'sanctum')->getJson("/api/erp/hr/employees/{$id}")->assertJsonPath('data.status', 'exited');
        $this->assertSame('suspended', $hr['employee']->fresh()->status);
    }
}
