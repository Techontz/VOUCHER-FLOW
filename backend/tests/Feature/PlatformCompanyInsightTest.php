<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Voucher;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * The super admin's read-only views into one company: they must show that
 * company's real data, only that company's data, and only to a super admin.
 */
class PlatformCompanyInsightTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function superAdmin(): User
    {
        return User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);
    }

    public function test_every_view_shows_only_the_selected_company(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $other = $this->makeTenant('Zamani Freight');
        $mine = $this->makeVoucher($acme, amount: 300000);
        $this->makeVoucher($other, amount: 999000);
        $super = $this->superAdmin();
        $base = "/api/platform/companies/{$acme['company']->id}";

        $vouchers = $this->actingAs($super, 'sanctum')->getJson("$base/vouchers?per_page=100")->assertOk();
        $this->assertSame([$mine->id], collect($vouchers->json('data'))->pluck('id')->all());
        $this->assertEquals(300000, $vouchers->json('meta.total_amount'));

        $emails = collect($this->getJson("$base/users?per_page=100")->assertOk()->json('data'))->pluck('email');
        $this->assertTrue($emails->contains($acme['employee']->email));
        $this->assertFalse($emails->contains($other['employee']->email), 'Another company\'s user was listed.');

        $departments = collect($this->getJson("$base/departments")->assertOk()->json('data'));
        $this->assertSame(['Operations'], $departments->pluck('name')->all());
        $this->assertSame($acme['hod']->name, $departments->first()['hod']['name']);

        $overview = $this->getJson("$base/overview")->assertOk()->json('data');
        $this->assertSame(1, $overview['vouchers']['total']);
        $this->assertSame(1, $overview['people']['departments']);

        $workflows = $this->getJson("$base/workflows")->assertOk()->json('data');
        $this->assertNotEmpty($workflows['workflows']);
        $this->assertNotNull($workflows['routing']);
        $this->assertSame('Operations', $workflows['routing']['departments'][0]['name']);
    }

    public function test_voucher_filters_apply(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $small = $this->makeVoucher($acme, amount: 100000);
        $large = $this->makeVoucher($acme, amount: 900000);
        $super = $this->superAdmin();
        $base = "/api/platform/companies/{$acme['company']->id}/vouchers";

        $ids = fn (string $qs) => collect($this->actingAs($super, 'sanctum')->getJson("$base?$qs")->assertOk()->json('data'))->pluck('id')->all();

        $this->assertSame([$large->id], $ids('min_amount=500000'));
        $this->assertSame([$small->id], $ids('max_amount=500000'));
        $this->assertSame([], $ids('status=paid'));
        $this->assertEqualsCanonicalizing([$small->id, $large->id], $ids('department_id='.$acme['department']->id));
    }

    public function test_the_views_are_closed_to_everyone_but_the_super_admin(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $base = "/api/platform/companies/{$acme['company']->id}";

        foreach (['overview', 'users', 'departments', 'workflows', 'vouchers'] as $view) {
            $this->actingAs($acme['admin'], 'sanctum')->getJson("$base/$view")->assertForbidden();
        }
    }

    public function test_reading_a_company_changes_nothing_and_leaves_no_tenant_behind(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $this->makeVoucher($acme);
        $before = app(TenantContext::class)->forCompany($acme['company'], fn () => Voucher::count());

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->getJson("/api/platform/companies/{$acme['company']->id}/overview")->assertOk();

        $this->assertSame($before, app(TenantContext::class)->forCompany($acme['company'], fn () => Voucher::count()));
        $this->assertNull(app(TenantContext::class)->company());
    }
}
