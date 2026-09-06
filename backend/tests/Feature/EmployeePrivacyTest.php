<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\User;
use App\Models\Voucher;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * "Employees must only see their own data and vouchers." Row-level visibility
 * sits on top of tenant isolation, and both are checked here.
 */
class EmployeePrivacyTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    public function test_an_employee_sees_only_their_own_vouchers(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $colleague = User::create([
            'company_id' => $t['company']->id,
            'name' => 'Second Employee',
            'email' => 'second@acme-trading.test',
            'password' => 'Password123!',
            'role' => User::ROLE_EMPLOYEE,
            'department_id' => $t['department']->id,
            'status' => 'active',
        ]);

        $mine = $this->makeVoucher($t, $t['employee']);
        $theirs = $this->makeVoucher($t, $colleague);

        $ids = collect(
            $this->actingAs($t['employee'], 'sanctum')->getJson('/api/vouchers?per_page=100')->json('data')
        )->pluck('id');

        $this->assertTrue($ids->contains($mine->id));
        $this->assertFalse($ids->contains($theirs->id));

        $this->actingAs($t['employee'], 'sanctum')
            ->getJson("/api/vouchers/{$theirs->id}")
            ->assertForbidden();
    }

    public function test_an_employee_cannot_read_administrative_areas(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $employee = $t['employee'];

        $this->actingAs($employee, 'sanctum')->getJson('/api/employees')->assertForbidden();
        $this->actingAs($employee, 'sanctum')->getJson('/api/audit-logs')->assertForbidden();
        $this->actingAs($employee, 'sanctum')->getJson('/api/billing/invoices')->assertForbidden();
        $this->actingAs($employee, 'sanctum')->postJson('/api/departments', ['name' => 'Sneaky'])->assertForbidden();
    }

    public function test_an_employee_cannot_act_on_the_approval_step(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();

        $this->actingAs($t['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => 'data:image/png;base64,AAAA'])
            ->assertStatus(422);

        $this->actingAs($t['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/approve")
            ->assertStatus(422);
    }

    public function test_a_head_of_department_sees_only_the_departments_they_head(): void
    {
        $t = $this->makeTenant('Acme Trading');

        // A second department, headed by somebody else entirely.
        $otherHod = User::create([
            'company_id' => $t['company']->id,
            'name' => 'Other Head',
            'email' => 'otherhod@acme-trading.test',
            'password' => 'Password123!',
            'role' => User::ROLE_HOD,
            'status' => 'active',
        ]);

        $otherDept = Department::create([
            'company_id' => $t['company']->id,
            'name' => 'Procurement',
            'hod_user_id' => $otherHod->id,
            'manager_user_id' => $t['manager']->id,
        ]);

        $outside = $this->makeVoucher($t);
        $outside->forceFill(['department_id' => $otherDept->id])->save();
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$outside->id}/submit")->assertOk();

        $ids = collect(
            $this->actingAs($t['hod'], 'sanctum')->getJson('/api/vouchers?per_page=100')->json('data')
        )->pluck('id');

        $this->assertFalse($ids->contains($outside->id), 'An HOD saw a department they do not head.');
    }

    public function test_other_peoples_drafts_are_never_visible(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $draft = $this->makeVoucher($t);

        foreach ([$t['hod'], $t['manager']] as $approver) {
            $ids = collect(
                $this->actingAs($approver, 'sanctum')->getJson('/api/vouchers?per_page=100')->json('data')
            )->pluck('id');

            $this->assertFalse($ids->contains($draft->id), 'A draft leaked to an approver.');
        }
    }

    public function test_reports_inherit_the_same_visibility(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $colleague = User::create([
            'company_id' => $t['company']->id,
            'name' => 'Second Employee',
            'email' => 'second@acme-trading.test',
            'password' => 'Password123!',
            'role' => User::ROLE_EMPLOYEE,
            'department_id' => $t['department']->id,
            'status' => 'active',
        ]);

        $this->makeVoucher($t, $t['employee']);
        $this->makeVoucher($t, $colleague);

        $rows = $this->actingAs($t['employee'], 'sanctum')
            ->getJson('/api/reports/vouchers')
            ->assertOk()
            ->json('rows');

        // Column 4 is the requester; an employee's report contains only their own.
        foreach ($rows as $row) {
            $this->assertSame($t['employee']->name, $row[4]);
        }
    }

    public function test_the_pdf_follows_the_same_rules(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $colleague = User::create([
            'company_id' => $t['company']->id,
            'name' => 'Second Employee',
            'email' => 'second@acme-trading.test',
            'password' => 'Password123!',
            'role' => User::ROLE_EMPLOYEE,
            'status' => 'active',
        ]);

        $mine = $this->makeVoucher($t, $t['employee']);
        $theirs = $this->makeVoucher($t, $colleague);

        // Printable at every stage for its owner, including as a draft.
        $this->actingAs($t['employee'], 'sanctum')
            ->get("/api/vouchers/{$mine->id}/pdf")
            ->assertOk()
            ->assertHeader('content-type', 'application/pdf');

        $this->actingAs($t['employee'], 'sanctum')
            ->get("/api/vouchers/{$theirs->id}/pdf")
            ->assertForbidden();
    }
}
