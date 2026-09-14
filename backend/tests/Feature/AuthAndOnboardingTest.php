<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\User;
use App\Models\VoucherType;
use App\Models\Workflow;
use App\Support\TenantContext;
use Database\Seeders\PlanSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

class AuthAndOnboardingTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    public function test_registering_provisions_a_complete_tenant(): void
    {
        $this->seed(PlanSeeder::class);

        $response = $this->postJson('/api/auth/register', [
            'company_name' => 'Northwind Traders',
            'business_email' => 'accounts@northwind.test',
            'name' => 'Amina Said',
            'email' => 'amina@northwind.test',
            'password' => 'Password123!',
            'password_confirmation' => 'Password123!',
        ])->assertCreated();

        $this->assertNotEmpty($response->json('token'));
        $this->assertSame('company_admin', $response->json('user.role'));

        $company = Company::where('name', 'Northwind Traders')->firstOrFail();
        $this->assertSame('trial', $company->status);
        $this->assertNotNull($company->trial_ends_at);

        // A new tenant starts with voucher types and a default route.
        app(TenantContext::class)->forCompany($company, function () {
            $this->assertGreaterThan(0, VoucherType::count());

            $workflow = Workflow::with('steps')->where('is_default', true)->firstOrFail();
            // Request → HOD signs → CEO approves → Cashier pays.
            $this->assertCount(4, $workflow->steps);

            $hod = $workflow->steps->firstWhere('role', 'hod');
            $this->assertTrue($hod->can_sign, 'The HOD step should sign.');
            $this->assertFalse($hod->can_approve, 'The HOD step must not approve.');

            $cashier = $workflow->steps->firstWhere('role', 'cashier');
            $this->assertTrue($cashier->can_pay, 'The cashier step should release money.');
            $this->assertFalse($cashier->can_approve, 'Paying is not approving.');
        });
    }

    public function test_new_accounts_start_on_the_light_theme(): void
    {
        $this->seed(PlanSeeder::class);

        $this->postJson('/api/auth/register', [
            'company_name' => 'Northwind Traders',
            'business_email' => 'accounts@northwind.test',
            'name' => 'Amina Said',
            'email' => 'amina@northwind.test',
            'password' => 'Password123!',
            'password_confirmation' => 'Password123!',
        ])->assertCreated()->assertJsonPath('user.theme', 'light');

        $this->assertSame('light', Company::where('name', 'Northwind Traders')->firstOrFail()->theme);

        // An invited colleague starts light too.
        $admin = User::where('email', 'amina@northwind.test')->firstOrFail();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/employees', [
                'name' => 'Joseph Mbwana',
                'email' => 'joseph@northwind.test',
                'role' => 'employee',
            ])
            ->assertCreated()
            ->assertJsonPath('data.theme', 'light');
    }

    public function test_dark_remains_a_choice_that_is_remembered(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['employee'], 'sanctum')
            ->putJson('/api/profile', ['theme' => 'dark'])
            ->assertOk()
            ->assertJsonPath('data.theme', 'dark');

        $this->assertSame('dark', $t['employee']->fresh()->theme);

        // The choice comes back on the next sign-in rather than reverting to light.
        $this->postJson('/api/auth/login', [
            'email' => $t['employee']->email,
            'password' => 'Password123!',
        ])->assertOk()->assertJsonPath('user.theme', 'dark');
    }

    public function test_the_same_address_can_belong_to_two_companies(): void
    {
        $this->seed(PlanSeeder::class);

        $payload = fn (string $slug) => [
            'company_name' => ucfirst($slug).' Ltd',
            'business_email' => "accounts@{$slug}.test",
            'name' => 'Shared Person',
            'email' => 'shared@example.test',
            'password' => 'Password123!',
            'password_confirmation' => 'Password123!',
        ];

        $this->postJson('/api/auth/register', $payload('alpha'))->assertCreated();
        $this->postJson('/api/auth/register', $payload('beta'))->assertCreated();

        $this->assertSame(2, User::where('email', 'shared@example.test')->count());
    }

    public function test_sign_in_rejects_bad_credentials_and_records_good_ones(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->postJson('/api/auth/login', [
            'email' => $t['employee']->email,
            'password' => 'wrong-password',
        ])->assertStatus(422);

        $this->postJson('/api/auth/login', [
            'email' => $t['employee']->email,
            'password' => 'Password123!',
        ])->assertOk()->assertJsonStructure(['token', 'user', 'company']);

        $this->assertNotNull($t['employee']->fresh()->last_login_at);
    }

    public function test_password_reset_runs_through_a_one_time_code(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $code = $this->postJson('/api/auth/forgot-password', ['email' => $t['employee']->email])
            ->assertOk()
            ->json('otp.code');

        $this->assertNotNull($code, 'A code should be returned outside production.');

        $this->postJson('/api/auth/reset-password', [
            'email' => $t['employee']->email,
            'code' => '000000',
            'password' => 'BrandNew123!',
            'password_confirmation' => 'BrandNew123!',
        ])->assertStatus(422);

        $this->postJson('/api/auth/reset-password', [
            'email' => $t['employee']->email,
            'code' => $code,
            'password' => 'BrandNew123!',
            'password_confirmation' => 'BrandNew123!',
        ])->assertOk();

        $this->postJson('/api/auth/login', [
            'email' => $t['employee']->email,
            'password' => 'BrandNew123!',
        ])->assertOk();
    }

    public function test_forgot_password_does_not_reveal_whether_an_account_exists(): void
    {
        $this->seed(PlanSeeder::class);

        $this->postJson('/api/auth/forgot-password', ['email' => 'nobody@nowhere.test'])
            ->assertOk()
            ->assertJsonPath('message', 'If that address matches an account, a reset code is on its way.');
    }

    public function test_numbering_is_sequential_and_per_tenant(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $other = $this->makeTenant('Zamani Freight');

        $first = $this->makeVoucher($acme)->number;
        $second = $this->makeVoucher($acme)->number;
        $foreign = $this->makeVoucher($other)->number;

        $year = now()->format('Y');
        $this->assertSame("PV-{$year}-000001", $first);
        $this->assertSame("PV-{$year}-000002", $second);

        // A second tenant starts its own sequence at one.
        $this->assertSame("PV-{$year}-000001", $foreign);
    }

    public function test_a_saved_signature_can_be_stored_and_reused(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

        $this->actingAs($t['hod'], 'sanctum')
            ->postJson('/api/profile/signature', ['signature' => $png])
            ->assertOk();

        $this->assertTrue($t['hod']->fresh()->signature_data !== null);

        // Signing without supplying an image falls back to the saved one.
        $voucher = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit");

        $this->actingAs($t['hod'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/sign", ['use_saved_signature' => true])
            ->assertOk()
            ->assertJsonPath('data.status_key', 'signed_pending_submit');
    }

    public function test_the_audit_log_records_who_did_what(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();

        $entries = collect(
            $this->actingAs($t['admin'], 'sanctum')->getJson('/api/audit-logs?per_page=50')->json('data')
        );

        $submitted = $entries->firstWhere('action', 'voucher.submitted');
        $this->assertNotNull($submitted, 'The submission should be on the record.');
        $this->assertSame($t['employee']->name, $submitted['actor']['name']);
    }
}
