<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Invoice;
use App\Models\Plan;
use App\Models\Subscription;
use App\Models\User;
use App\Services\PaymentGateway;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/** Extend, cancel and reactivate a subscription, and the states each needs. */
class PlatformSubscriptionTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function operator(): User
    {
        return User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);
    }

    /** A tenant on a paid monthly subscription. */
    private function paying(): array
    {
        $t = $this->makeTenant('Acme Trading');
        $sub = app(TenantContext::class)->forCompany($t['company'], fn () => app(PaymentGateway::class)
            ->subscribe($t['company'], Plan::where('code', 'starter')->first(), 'monthly'));

        return [$t, Subscription::query()->withoutGlobalScopes()->find($sub->id)];
    }

    public function test_the_list_shows_every_subscription_with_its_company(): void
    {
        [$t, $sub] = $this->paying();

        $this->actingAs($this->operator(), 'sanctum')->getJson('/api/platform/subscriptions')
            ->assertOk()
            ->assertJsonPath('data.0.id', $sub->id)
            ->assertJsonPath('data.0.company', 'Acme Trading')
            ->assertJsonPath('summary.running', 1);
    }

    public function test_a_running_subscription_is_extended(): void
    {
        [$t, $sub] = $this->paying();
        $end = $sub->current_period_end;

        $this->actingAs($this->operator(), 'sanctum')
            ->postJson("/api/platform/subscriptions/{$sub->id}/extend", ['days' => 30])
            ->assertOk();

        $this->assertSame($end->copy()->addDays(30)->toDateString(), $sub->fresh()->current_period_end->toDateString());
        $this->assertSame($end->copy()->addDays(30)->toDateString(), $t['company']->fresh()->current_period_end->toDateString());
    }

    public function test_cancel_at_period_end_keeps_it_running_until_reactivated(): void
    {
        [$t, $sub] = $this->paying();
        $op = $this->operator();

        $this->actingAs($op, 'sanctum')->postJson("/api/platform/subscriptions/{$sub->id}/cancel", ['when' => 'period_end'])
            ->assertOk()->assertJsonPath('data.status', 'active')->assertJsonPath('data.cancel_at_period_end', true);
        $this->assertFalse($t['company']->fresh()->auto_renew);

        // Not twice.
        $this->actingAs($op, 'sanctum')->postJson("/api/platform/subscriptions/{$sub->id}/cancel", ['when' => 'period_end'])
            ->assertUnprocessable();

        $this->actingAs($op, 'sanctum')->postJson("/api/platform/subscriptions/{$sub->id}/reactivate")
            ->assertOk()->assertJsonPath('data.cancel_at_period_end', false);
        $this->assertTrue($t['company']->fresh()->auto_renew);

        // Running and not cancelled: nothing to reactivate.
        $this->actingAs($op, 'sanctum')->postJson("/api/platform/subscriptions/{$sub->id}/reactivate")
            ->assertUnprocessable();

        $this->assertTrue(AuditLog::where('action', 'platform.subscription_cancel_scheduled')->exists());
        $this->assertTrue(AuditLog::where('action', 'platform.subscription_reactivated')->exists());
    }

    public function test_cancel_immediately_closes_access_and_reactivate_starts_a_new_period(): void
    {
        [$t, $sub] = $this->paying();
        $op = $this->operator();

        $this->actingAs($op, 'sanctum')->postJson("/api/platform/subscriptions/{$sub->id}/cancel", ['when' => 'immediately'])
            ->assertOk()->assertJsonPath('data.status', 'cancelled');
        $this->assertSame('cancelled', $t['company']->fresh()->status);
        $this->assertFalse($t['company']->fresh()->isUsable());

        // A cancelled subscription can be neither cancelled again nor extended.
        $this->actingAs($op, 'sanctum')->postJson("/api/platform/subscriptions/{$sub->id}/cancel", ['when' => 'immediately'])
            ->assertUnprocessable();
        $this->actingAs($op, 'sanctum')->postJson("/api/platform/subscriptions/{$sub->id}/extend", ['days' => 5])
            ->assertUnprocessable();
        $this->actingAs($op, 'sanctum')->postJson("/api/platform/companies/{$t['company']->id}/extend", ['days' => 5])
            ->assertUnprocessable();

        $this->actingAs($op, 'sanctum')->postJson("/api/platform/subscriptions/{$sub->id}/reactivate")
            ->assertOk()->assertJsonPath('data.status', 'active');

        $company = $t['company']->fresh();
        $this->assertSame('active', $company->status);
        $this->assertTrue($company->isUsable());
        $this->assertSame(now()->addMonth()->toDateString(), $company->current_period_end->toDateString());
    }

    public function test_an_old_subscription_cannot_be_reactivated_beside_a_running_one(): void
    {
        [$t, $sub] = $this->paying();

        // Changing plan cancels the old subscription and starts a new one.
        $this->actingAs($this->operator(), 'sanctum')
            ->postJson("/api/platform/companies/{$t['company']->id}/change-plan", ['plan_id' => Plan::where('code', 'business')->first()->id])
            ->assertOk();

        $this->actingAs($this->operator(), 'sanctum')->postJson("/api/platform/subscriptions/{$sub->id}/reactivate")
            ->assertUnprocessable();
        $this->assertTrue(AuditLog::where('action', 'platform.company_plan_changed')->exists());
    }

    public function test_an_invoice_is_raised_once_and_can_be_marked_paid(): void
    {
        [$t, $sub] = $this->paying();
        $op = $this->operator();

        $invoice = $this->actingAs($op, 'sanctum')->postJson("/api/platform/subscriptions/{$sub->id}/invoice")
            ->assertCreated()->json('data');
        $this->actingAs($op, 'sanctum')->postJson("/api/platform/subscriptions/{$sub->id}/invoice")
            ->assertUnprocessable();

        $this->actingAs($op, 'sanctum')->getJson('/api/platform/subscriptions')
            ->assertJsonPath("unpaid_invoices.{$sub->id}.id", $invoice['id']);

        $this->actingAs($op, 'sanctum')->postJson("/api/platform/payments/{$invoice['id']}/mark-paid", ['reference' => 'BANK-1'])
            ->assertOk()->assertJsonPath('data.status', 'paid');
        $this->assertSame('paid', Invoice::query()->withoutGlobalScopes()->find($invoice['id'])->status);
    }
}
