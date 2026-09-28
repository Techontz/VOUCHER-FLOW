<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherType;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * A voucher belongs to its requester's department and only ever reaches that
 * department's HOD — one department never sends a voucher to another.
 */
class DepartmentBoundaryTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private const SIGNATURE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    /** A second department in the same company, with its own head. */
    private function otherDepartment(array $t): array
    {
        $hod = User::create([
            'company_id' => $t['company']->id,
            'name' => 'Finance Head',
            'email' => 'finance-hod@acme-trading.test',
            'password' => 'Password123!',
            'role' => User::ROLE_HOD,
            'status' => 'active',
        ]);

        $department = Department::create([
            'company_id' => $t['company']->id,
            'name' => 'Finance',
            'hod_user_id' => $hod->id,
        ]);

        $hod->update(['department_id' => $department->id]);

        return compact('hod', 'department');
    }

    private function typeId(array $t): int
    {
        return VoucherType::withoutGlobalScopes()
            ->where('company_id', $t['company']->id)
            ->where('code', 'payment')
            ->value('id');
    }

    public function test_a_voucher_cannot_be_raised_into_another_department(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $other = $this->otherDepartment($t);

        $this->actingAs($t['employee'], 'sanctum')
            ->postJson('/api/vouchers', [
                'voucher_type_id' => $this->typeId($t),
                'department_id' => $other['department']->id,
                'payee' => 'Supplier Ltd', 'purpose' => 'Stationery', 'amount' => 50000,
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('department_id');

        $this->assertSame(0, Voucher::withoutGlobalScopes()->count());
    }

    public function test_a_voucher_is_always_raised_in_the_requesters_department(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['employee'], 'sanctum')
            ->postJson('/api/vouchers', [
                'voucher_type_id' => $this->typeId($t),
                'payee' => 'Supplier Ltd', 'purpose' => 'Stationery', 'amount' => 50000,
            ])
            ->assertCreated()
            ->assertJsonPath('data.department.id', $t['department']->id);
    }

    public function test_a_draft_cannot_be_moved_to_another_department(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $other = $this->otherDepartment($t);
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')
            ->putJson("/api/vouchers/{$voucher->id}", ['department_id' => $other['department']->id])
            ->assertStatus(422);

        $this->assertSame($t['department']->id, $voucher->fresh()->department_id);
    }

    public function test_another_departments_hod_never_receives_the_voucher(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $other = $this->otherDepartment($t);

        // Even with no HOD of its own, the voucher does not pass to Finance's head.
        $t['department']->update(['hod_user_id' => null]);
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/submit")
            ->assertOk();

        $this->actingAs($other['hod'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE])
            ->assertStatus(403);

        $pending = $this->actingAs($other['hod'], 'sanctum')
            ->getJson('/api/vouchers/pending')->assertOk();

        $this->assertNotContains($voucher->id, collect($pending->json('data'))->pluck('id'));
    }
}
