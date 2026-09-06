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
 * One central database, strict company isolation. These tests exist because the
 * guarantee is load-bearing: a regression here leaks another company's money.
 */
class TenantIsolationTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    public function test_a_voucher_from_another_company_is_not_readable(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $other = $this->makeTenant('Zamani Freight');

        $foreign = $this->makeVoucher($other);

        $this->actingAs($acme['admin'], 'sanctum')
            ->getJson("/api/vouchers/{$foreign->id}")
            ->assertNotFound();
    }

    public function test_listings_never_cross_a_company_boundary(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $other = $this->makeTenant('Zamani Freight');

        $this->makeVoucher($acme);
        $this->makeVoucher($other);

        $response = $this->actingAs($acme['admin'], 'sanctum')
            ->getJson('/api/vouchers?per_page=100')
            ->assertOk();

        $ids = collect($response->json('data'))->pluck('id');
        $foreignIds = app(TenantContext::class)->forCompany(
            $other['company'],
            fn () => Voucher::pluck('id'),
        );

        $this->assertTrue($ids->intersect($foreignIds)->isEmpty(), 'A foreign voucher appeared in the listing.');
    }

    public function test_people_and_departments_are_scoped_to_the_company(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $this->makeTenant('Zamani Freight');

        $emails = collect(
            $this->actingAs($acme['admin'], 'sanctum')->getJson('/api/employees?per_page=100')->json('data')
        )->pluck('email');

        $this->assertTrue($emails->every(fn ($email) => str_ends_with($email, '@acme-trading.test')), (string) $emails);

        $departments = collect(
            $this->actingAs($acme['admin'], 'sanctum')->getJson('/api/departments')->json('data')
        )->pluck('id');

        $foreign = Department::withoutGlobalScopes()
            ->where('company_id', '!=', $acme['company']->id)
            ->pluck('id');

        $this->assertTrue($departments->intersect($foreign)->isEmpty());
    }

    public function test_an_admin_cannot_modify_another_companys_user(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $other = $this->makeTenant('Zamani Freight');

        $this->actingAs($acme['admin'], 'sanctum')
            ->putJson("/api/employees/{$other['employee']->id}", ['name' => 'Hijacked'])
            ->assertNotFound();

        $this->assertNotSame('Hijacked', $other['employee']->fresh()->name);
    }

    public function test_the_tenant_scope_fails_closed_without_a_resolved_company(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $this->makeVoucher($acme);

        // No tenant, no platform flag — the scope must match nothing at all.
        app(TenantContext::class)->clear();

        $this->assertSame(0, Voucher::count());
        $this->assertGreaterThan(0, Voucher::withoutGlobalScopes()->count());
    }

    public function test_a_company_admin_cannot_reach_the_platform_area(): void
    {
        $acme = $this->makeTenant('Acme Trading');

        $this->actingAs($acme['admin'], 'sanctum')
            ->getJson('/api/platform/companies')
            ->assertForbidden();
    }

    public function test_a_super_admin_reads_across_companies(): void
    {
        $this->makeTenant('Acme Trading');
        $this->makeTenant('Zamani Freight');

        $super = User::create([
            'company_id' => null,
            'name' => 'Platform Operator',
            'email' => 'super@vouchflow.test',
            'password' => 'Password123!',
            'role' => User::ROLE_SUPER_ADMIN,
            'status' => 'active',
        ]);

        $this->actingAs($super, 'sanctum')
            ->getJson('/api/platform/companies')
            ->assertOk()
            ->assertJsonCount(2, 'data');
    }
}
