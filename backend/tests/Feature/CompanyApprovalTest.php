<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\AuditLog;
use App\Models\Company;
use App\Models\Invoice;
use App\Models\OtpCode;
use App\Models\Plan;
use App\Models\Subscription;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * A company that registers itself waits for the platform's approval before it
 * can use the product, and pays — if it wants to — while it waits.
 */
class CompanyApprovalTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function register(array $extra = []): TestResponse
    {
        $this->seedPlans();

        return $this->postJson('/api/auth/register', [
            'company_name' => 'Northwind Traders',
            'business_email' => 'accounts@northwind.test',
            'name' => 'Amina Said',
            'email' => 'amina@northwind.test',
            'password' => 'Password123!',
            'password_confirmation' => 'Password123!',
        ] + $extra)->assertCreated();
    }

    private function admin(): User
    {
        return User::where('email', 'amina@northwind.test')->firstOrFail();
    }

    private function company(): Company
    {
        return Company::where('name', 'Northwind Traders')->firstOrFail();
    }

    private function superAdmin(): User
    {
        return User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);
    }

    public function test_self_registration_creates_a_pending_company_without_a_trial(): void
    {
        $response = $this->register(['plan_code' => 'business']);

        $company = $this->company();
        $this->assertSame('pending', $company->status);
        $this->assertTrue($company->isPending());
        $this->assertFalse($company->isUsable());
        $this->assertNull($company->trial_ends_at);
        $this->assertSame(0, Subscription::withoutGlobalScopes()->where('company_id', $company->id)
            ->whereIn('status', ['trialing', 'active'])->count());

        // The chosen plan is still on show.
        $response->assertJsonPath('company.status', 'pending')
            ->assertJsonPath('company.is_usable', false)
            ->assertJsonPath('company.plan.code', 'business');

        $this->actingAs($this->admin(), 'sanctum')->getJson('/api/auth/me')
            ->assertOk()
            ->assertJsonPath('company.status', 'pending')
            ->assertJsonPath('company.plan.code', 'business');
    }

    public function test_the_platform_hears_about_a_new_registration(): void
    {
        $super = $this->superAdmin();

        $this->register();

        $this->assertSame(1, AppNotification::where('user_id', $super->id)->where('type', 'company.pending')->count());
    }

    public function test_a_platform_created_company_still_starts_on_a_trial(): void
    {
        $this->seedPlans();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/platform/companies', [
                'company' => ['name' => 'Direct Ltd', 'email' => 'accounts@direct.test'],
                'admin' => ['name' => 'Direct Admin', 'email' => 'admin@direct.test', 'password' => 'Password123!'],
            ])
            ->assertCreated()
            ->assertJsonPath('data.status', 'trial');
    }

    public function test_a_pending_company_is_held_out_of_the_product(): void
    {
        $this->register();
        $admin = $this->admin();

        $blocked = fn (TestResponse $r) => $r->assertForbidden()
            ->assertExactJson([
                'message' => 'Your company is waiting for approval. You can choose a plan and pay while you wait.',
                'code' => 'company_pending',
                'status' => 'pending',
            ]);

        $blocked($this->actingAs($admin, 'sanctum')->postJson('/api/employees', [
            'name' => 'Joseph Mbwana', 'email' => 'joseph@northwind.test', 'role' => 'employee',
        ]));
        $blocked($this->actingAs($admin, 'sanctum')->getJson('/api/vouchers'));
        $blocked($this->actingAs($admin, 'sanctum')->getJson('/api/dashboard'));
        $blocked($this->actingAs($admin, 'sanctum')->getJson('/api/employees'));

        $this->assertSame(1, User::withoutGlobalScopes()->where('company_id', $admin->company_id)->count());
    }

    public function test_a_pending_company_keeps_its_account_profile_and_billing(): void
    {
        $this->register();
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->getJson('/api/auth/me')->assertOk();
        $this->actingAs($admin, 'sanctum')->getJson('/api/auth/sessions')->assertOk();
        $this->actingAs($admin, 'sanctum')->putJson('/api/profile', ['theme' => 'light'])->assertOk();
        $this->actingAs($admin, 'sanctum')->getJson('/api/company')->assertOk();
        $this->actingAs($admin, 'sanctum')->getJson('/api/notifications')->assertOk();
        $this->actingAs($admin, 'sanctum')->postJson('/api/notifications/read-all')->assertOk();
        $this->actingAs($admin, 'sanctum')->getJson('/api/billing/subscription')
            ->assertOk()
            ->assertJsonPath('company_status', 'pending');
        $this->actingAs($admin, 'sanctum')->getJson('/api/billing/invoices')->assertOk();
    }

    public function test_a_pending_company_can_finish_its_profile_and_logo(): void
    {
        Storage::fake('public');

        $this->register();
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')
            ->putJson('/api/company', ['trading_name' => 'Northwind', 'tin' => '123-456-789', 'primary_color' => '#1d4ed8'])
            ->assertOk();

        $this->actingAs($admin, 'sanctum')
            ->post('/api/company/logo', ['logo' => UploadedFile::fake()->image('logo.png', 200, 80)], ['Accept' => 'application/json'])
            ->assertOk();

        $this->actingAs($admin, 'sanctum')->deleteJson('/api/company/logo')->assertOk();

        $company = $this->company();
        $this->assertSame('Northwind', $company->trading_name);
        $this->assertSame('123-456-789', $company->tin);
        $this->assertSame('pending', $company->status);
    }

    public function test_paying_while_pending_records_the_period_but_stays_pending(): void
    {
        $this->register();
        $admin = $this->admin();

        $subscribed = $this->actingAs($admin, 'sanctum')
            ->postJson('/api/billing/subscribe', ['plan_id' => Plan::where('code', 'business')->value('id')])
            ->assertCreated();

        $this->assertSame('pending', $this->company()->status);
        $this->assertNull($this->company()->current_period_end, 'Choosing a plan is not paying for it.');

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/billing/invoices/'.$subscribed->json('invoice.id').'/pay', [
                'method' => 'mobile_money', 'reference' => '255712418226',
            ])
            ->assertOk()
            ->assertJsonPath('invoice.status', 'paid');

        $company = $this->company();
        $this->assertSame('pending', $company->status);
        $this->assertTrue($company->current_period_end->isFuture());
        $this->assertSame('paid', Invoice::withoutGlobalScopes()->findOrFail($subscribed->json('invoice.id'))->status);

        // Still held out until the platform approves.
        $this->actingAs($admin, 'sanctum')->getJson('/api/vouchers')->assertForbidden();
    }

    public function test_approving_an_unpaid_company_starts_its_trial(): void
    {
        $this->register(['plan_code' => 'business']);
        $company = $this->company();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson("/api/platform/companies/{$company->id}/approve")
            ->assertOk()
            ->assertJsonPath('data.status', 'trial')
            ->assertJsonPath('data.is_usable', true);

        $company->refresh();
        $this->assertSame('trial', $company->status);
        $this->assertTrue($company->trial_ends_at->isFuture());
        $this->assertSame(1, Subscription::withoutGlobalScopes()->where('company_id', $company->id)
            ->where('status', 'trialing')->count());
        $this->assertTrue(AuditLog::withoutGlobalScopes()->where('action', 'platform.company_approved')->exists());
        $this->assertTrue(AppNotification::where('user_id', $this->admin()->id)->where('type', 'company.approved')->exists());

        // And the company is now in.
        $this->actingAs($this->admin(), 'sanctum')->getJson('/api/vouchers')->assertOk();
        $this->actingAs($this->admin(), 'sanctum')
            ->postJson('/api/employees', ['name' => 'Joseph Mbwana', 'email' => 'joseph@northwind.test', 'role' => 'employee'])
            ->assertCreated();
    }

    public function test_approving_a_company_that_already_paid_makes_it_active(): void
    {
        $this->register();
        $admin = $this->admin();

        $invoiceId = $this->actingAs($admin, 'sanctum')
            ->postJson('/api/billing/subscribe', ['plan_id' => Plan::where('code', 'business')->value('id')])
            ->json('invoice.id');

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/billing/invoices/{$invoiceId}/pay", ['method' => 'mobile_money', 'reference' => '255712418226'])
            ->assertOk();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson("/api/platform/companies/{$this->company()->id}/approve")
            ->assertOk()
            ->assertJsonPath('data.status', 'active');
    }

    public function test_only_a_pending_company_can_be_approved(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson("/api/platform/companies/{$t['company']->id}/approve")
            ->assertStatus(422);

        $this->assertSame('active', $t['company']->fresh()->status);
    }

    public function test_only_a_super_admin_can_approve(): void
    {
        $this->register();
        $other = $this->makeTenant('Acme Trading');

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/platform/companies/{$this->company()->id}/approve")
            ->assertForbidden();

        $this->actingAs($other['admin'], 'sanctum')
            ->postJson("/api/platform/companies/{$this->company()->id}/approve")
            ->assertForbidden();

        $this->assertSame('pending', $this->company()->status);
    }

    public function test_the_platform_can_find_pending_companies(): void
    {
        $this->register();
        $this->makeTenant('Acme Trading');
        $super = $this->superAdmin();

        $this->actingAs($super, 'sanctum')
            ->getJson('/api/platform/companies?status=pending')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.name', 'Northwind Traders');

        $dashboard = $this->actingAs($super, 'sanctum')->getJson('/api/dashboard')->assertOk();

        $dashboard->assertJsonPath('data.view', 'platform')
            ->assertJsonPath('data.pending_companies', 1)
            ->assertJsonPath('data.attention.0.name', 'Northwind Traders')
            ->assertJsonPath('data.attention.0.status', 'pending');
    }

    public function test_registration_skips_the_email_code_when_mail_cannot_be_sent(): void
    {
        Notification::fake();
        config(['vouchflow.registration_email_verification' => 'auto', 'mail.default' => 'log']);

        $response = $this->register()
            ->assertJsonPath('requires_verification', false)
            ->assertJsonPath('registration_email_verification', false)
            ->assertJsonMissingPath('otp');

        $this->assertNotEmpty($response->json('token'));
        $this->assertNotNull($this->admin()->email_verified_at);
        $this->assertSame(0, OtpCode::count());
    }

    public function test_registration_asks_for_the_email_code_when_mail_works(): void
    {
        Notification::fake();
        config(['vouchflow.registration_email_verification' => 'auto', 'mail.default' => 'smtp']);

        $this->register()
            ->assertJsonPath('requires_verification', true)
            ->assertJsonPath('otp.purpose', 'registration')
            ->assertJsonPath('otp.identifier', 'amina@northwind.test');

        $this->assertSame(1, OtpCode::where('purpose', 'registration')->count());
    }

    public function test_registration_verification_can_be_forced_either_way(): void
    {
        Notification::fake();

        config(['vouchflow.registration_email_verification' => 'true', 'mail.default' => 'log']);
        $this->register()->assertJsonPath('requires_verification', true);

        config(['vouchflow.registration_email_verification' => false, 'mail.default' => 'smtp']);
        $this->postJson('/api/auth/register', [
            'company_name' => 'Second Ltd',
            'business_email' => 'accounts@second.test',
            'name' => 'Second Admin',
            'email' => 'admin@second.test',
            'password' => 'Password123!',
            'password_confirmation' => 'Password123!',
        ])->assertCreated()
            ->assertJsonPath('requires_verification', false)
            ->assertJsonMissingPath('otp');
    }
}
