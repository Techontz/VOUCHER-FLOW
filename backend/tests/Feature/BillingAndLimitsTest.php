<?php

namespace Tests\Feature;

use App\Models\Invoice;
use App\Models\Plan;
use App\Models\User;
use App\Services\PaymentGateway;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

class BillingAndLimitsTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    public function test_a_payment_can_be_taken_and_the_period_rolls_forward(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $subscription = app(TenantContext::class)->forCompany(
            $t['company'],
            fn () => app(PaymentGateway::class)->subscribe($t['company'], Plan::where('code', 'business')->first()),
        );

        $invoice = app(TenantContext::class)->forCompany(
            $t['company'],
            fn () => app(PaymentGateway::class)->issueInvoice($t['company'], $subscription),
        );

        $this->actingAs($t['admin'], 'sanctum')
            ->postJson("/api/billing/invoices/{$invoice->id}/pay", [
                'method' => 'mobile_money',
                'reference' => '255712418226',
            ])
            ->assertOk()
            ->assertJsonPath('invoice.status', 'paid');

        $this->assertNotNull($invoice->fresh()->paid_at);
        $this->assertSame('active', $t['company']->fresh()->status);
    }

    public function test_a_declined_payment_is_reported_and_not_settled(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $subscription = app(TenantContext::class)->forCompany(
            $t['company'],
            fn () => app(PaymentGateway::class)->subscribe($t['company'], Plan::where('code', 'business')->first()),
        );
        $invoice = app(TenantContext::class)->forCompany(
            $t['company'],
            fn () => app(PaymentGateway::class)->issueInvoice($t['company'], $subscription),
        );

        // The sandbox declines any reference ending 0000.
        $this->actingAs($t['admin'], 'sanctum')
            ->postJson("/api/billing/invoices/{$invoice->id}/pay", [
                'method' => 'mobile_money',
                'reference' => '255710000000',
            ])
            ->assertStatus(422);

        $this->assertSame('failed', $invoice->fresh()->status);
    }

    public function test_an_expired_subscription_blocks_writes_but_not_reads(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $t['company']->forceFill([
            'status' => 'trial',
            'trial_ends_at' => now()->subDay(),
            'current_period_end' => now()->subDay(),
        ])->save();

        $this->actingAs($t['employee'], 'sanctum')
            ->getJson('/api/vouchers')
            ->assertOk();

        $this->actingAs($t['employee'], 'sanctum')
            ->postJson('/api/vouchers', [
                'voucher_type_id' => 1, 'payee' => 'X', 'purpose' => 'Y', 'amount' => 1000,
            ])
            ->assertStatus(402)
            ->assertJsonPath('code', 'subscription_inactive');
    }

    public function test_the_seat_limit_is_enforced(): void
    {
        $t = $this->makeTenant('Acme Trading');

        // A tiny plan, so the next invitation must be refused.
        $starter = Plan::where('code', 'starter')->first();
        $starter->forceFill(['max_users' => 2])->save();
        $t['company']->forceFill(['plan_id' => $starter->id])->save();

        $this->actingAs($t['admin'], 'sanctum')
            ->postJson('/api/employees', [
                'name' => 'One Too Many',
                'email' => 'extra@acme-trading.test',
                'role' => 'employee',
            ])
            ->assertStatus(422);
    }

    public function test_downgrading_below_current_usage_is_refused(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $starter = Plan::where('code', 'starter')->first();
        $starter->forceFill(['max_users' => 1])->save();

        $this->actingAs($t['admin'], 'sanctum')
            ->postJson('/api/billing/subscribe', ['plan_id' => $starter->id])
            ->assertStatus(422);
    }

    public function test_a_suspended_company_cannot_sign_in(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['company']->forceFill(['status' => 'suspended'])->save();

        $this->postJson('/api/auth/login', [
            'email' => $t['employee']->email,
            'password' => 'Password123!',
        ])->assertStatus(422);
    }

    public function test_suspending_a_company_revokes_its_sessions(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['employee']->createToken('web');

        $super = User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);

        $this->actingAs($super, 'sanctum')
            ->postJson("/api/platform/companies/{$t['company']->id}/suspend")
            ->assertOk();

        $this->assertSame(0, $t['employee']->fresh()->tokens()->count());
    }

    public function test_invoices_are_scoped_to_the_paying_company(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $other = $this->makeTenant('Zamani Freight');

        foreach ([$acme, $other] as $tenant) {
            app(TenantContext::class)->forCompany($tenant['company'], function () use ($tenant) {
                $sub = app(PaymentGateway::class)->subscribe($tenant['company'], Plan::where('code', 'business')->first());
                app(PaymentGateway::class)->issueInvoice($tenant['company'], $sub);
            });
        }

        $numbers = collect(
            $this->actingAs($acme['admin'], 'sanctum')->getJson('/api/billing/invoices')->json('data')
        )->pluck('company_id')->unique();

        $this->assertSame([$acme['company']->id], $numbers->values()->all());
        $this->assertGreaterThan(1, Invoice::withoutGlobalScopes()->count());
    }
}
