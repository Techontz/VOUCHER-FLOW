<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\User;
use App\Models\Voucher;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Reports are where history lives, so they are also where a permission mistake
 * does the most damage. The catalogue is filtered per role AND the endpoint
 * refuses what the catalogue withheld — the UI hiding a card is not a control.
 */
class ReportPermissionsTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    public function test_the_catalogue_is_narrowed_to_the_role(): void
    {
        $t = $this->makeTenant('Watercom Demo');

        $keys = fn ($user) => array_column(
            $this->actingAs($user, 'sanctum')->getJson('/api/reports')->assertOk()->json('data'),
            'key',
        );

        $this->assertSame(['vouchers', 'expenses'], $keys($t['employee']));
        $this->assertContains('payments', $keys($t['cashier']));
        $this->assertNotContains('approvals', $keys($t['cashier']));

        // An administrator sees the whole catalogue.
        $this->assertContains('approvals', $keys($t['admin']));
        $this->assertContains('employees', $keys($t['admin']));
    }

    public function test_a_report_outside_the_role_is_refused_by_the_api(): void
    {
        $t = $this->makeTenant('Watercom Demo');

        $this->actingAs($t['employee'], 'sanctum')
            ->getJson('/api/reports/employees')
            ->assertForbidden();

        $this->actingAs($t['employee'], 'sanctum')
            ->getJson('/api/reports/employees/export?format=csv')
            ->assertForbidden();
    }

    public function test_an_employees_report_contains_only_their_own_vouchers(): void
    {
        $t = $this->makeTenant('Watercom Demo');

        $mine = $this->makeVoucher($t, $t['employee']);

        $colleague = app(TenantContext::class)->forCompany($t['company'], fn () => User::create([
            'company_id' => $t['company']->id,
            'name' => 'Colleague', 'email' => 'colleague@watercom-demo.test',
            'password' => 'Password123!', 'role' => User::ROLE_EMPLOYEE,
            'status' => 'active', 'department_id' => $t['department']->id,
        ]));

        $theirs = $this->makeVoucher($t, $colleague);

        $rows = $this->actingAs($t['employee'], 'sanctum')
            ->getJson('/api/reports/vouchers')->assertOk()->json('rows');

        $numbers = array_column($rows, 0);
        $this->assertContains($mine->number, $numbers);
        $this->assertNotContains($theirs->number, $numbers, 'An employee must not see a colleague\'s voucher.');
    }

    public function test_a_department_filter_cannot_widen_the_scope(): void
    {
        $t = $this->makeTenant('Watercom Demo');

        // A second department this HOD does not head.
        $other = app(TenantContext::class)->forCompany($t['company'], fn () => Department::create([
            'company_id' => $t['company']->id, 'name' => 'Elsewhere', 'code' => 'ELS',
        ]));

        $outsider = $this->makeVoucher($t, $t['employee']);
        $outsider->forceFill(['department_id' => $other->id, 'status' => Voucher::STATUS_APPROVED])->save();

        // Asking for the department they do not head returns nothing, rather
        // than returning that department's rows.
        $rows = $this->actingAs($t['hod'], 'sanctum')
            ->getJson("/api/reports/vouchers?department_id={$other->id}")
            ->assertOk()->json('rows');

        $this->assertNotContains($outsider->number, array_column($rows, 0));
    }

    public function test_the_scope_ceiling_is_reported_to_the_client(): void
    {
        $t = $this->makeTenant('Watercom Demo');

        $this->assertSame(
            'own',
            $this->actingAs($t['employee'], 'sanctum')->getJson('/api/reports')->json('scope.level'),
        );

        $this->assertSame(
            'departments',
            $this->actingAs($t['hod'], 'sanctum')->getJson('/api/reports')->json('scope.level'),
        );

        $this->assertSame(
            'company',
            $this->actingAs($t['ceo'], 'sanctum')->getJson('/api/reports')->json('scope.level'),
        );
    }
}
