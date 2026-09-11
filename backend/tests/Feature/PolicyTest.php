<?php

namespace Tests\Feature;

use App\Models\Voucher;
use App\Models\Workflow;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Gate;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * The policies are the single door every authorisation question goes through.
 * These tests exist mainly to prove the door is actually there: an unregistered
 * policy fails open in the most dangerous way, by silently answering "allow".
 */
class PolicyTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private const SIGNATURE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    public function test_the_voucher_policy_is_registered_and_denies_across_tenants(): void
    {
        $mine = $this->makeTenant('Watercom Demo');
        $theirs = $this->makeTenant('Zamani Freight');

        $foreign = $this->makeVoucher($theirs);
        $ours = $this->makeVoucher($mine);

        // Inside the caller's own tenant, as the middleware arranges for a real
        // request. Asking outside one proves nothing: the tenant scope fails
        // closed with no company resolved, so everything is denied and a
        // missing policy would look exactly like a working one.
        app(TenantContext::class)->forCompany($mine['company'], function () use ($mine, $ours, $foreign) {
            $this->assertTrue(
                Gate::forUser($mine['admin'])->allows('view', $ours),
                'An administrator must be able to read their own company\'s voucher.',
            );

            $this->assertFalse(
                Gate::forUser($mine['admin'])->allows('view', $foreign),
                'A policy that is not registered would answer "allow" here.',
            );
        });
    }

    public function test_signing_and_approving_are_separate_permissions(): void
    {
        $t = $this->makeTenant('Watercom Demo');
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit");
        $voucher = $voucher->fresh();

        $hod = Gate::forUser($t['hod']);
        $this->assertTrue($hod->allows('sign', $voucher));
        $this->assertFalse($hod->allows('approve', $voucher), 'The HOD step signs only.');

        // And the CEO cannot sign ahead of the step reaching them.
        $ceo = Gate::forUser($t['ceo']);
        $this->assertFalse($ceo->allows('approve', $voucher));
    }

    public function test_only_a_paying_step_may_release_money(): void
    {
        $t = $this->makeTenant('Watercom Demo');
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit");
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE]);
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed");
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve");

        $voucher = $voucher->fresh();

        $this->assertTrue(Gate::forUser($t['cashier'])->allows('pay', $voucher));
        $this->assertFalse(Gate::forUser($t['employee'])->allows('pay', $voucher));
        $this->assertFalse(Gate::forUser($t['hod'])->allows('pay', $voucher));
        $this->assertFalse(Gate::forUser($t['ceo'])->allows('pay', $voucher));
    }

    public function test_reshaping_a_workflow_belongs_to_administrators(): void
    {
        $t = $this->makeTenant('Watercom Demo');

        $workflow = app(TenantContext::class)->forCompany(
            $t['company'],
            fn () => Workflow::where('is_default', true)->firstOrFail(),
        );

        $this->assertTrue(Gate::forUser($t['admin'])->allows('update', $workflow));

        // A workflow grants signing, approving and paying — so editing one is
        // the power to grant yourself all three.
        foreach (['employee', 'hod', 'ceo', 'cashier'] as $role) {
            $this->assertFalse(
                Gate::forUser($t[$role])->allows('update', $workflow),
                "A {$role} must not be able to reshape the approval route.",
            );
        }
    }

    public function test_branding_belongs_to_the_company_administrator(): void
    {
        $t = $this->makeTenant('Watercom Demo');
        $other = $this->makeTenant('Zamani Freight');

        $this->assertTrue(Gate::forUser($t['admin'])->allows('brand', $t['company']));
        $this->assertFalse(Gate::forUser($t['ceo'])->allows('brand', $t['company']));
        $this->assertFalse(
            Gate::forUser($other['admin'])->allows('brand', $t['company']),
            'An administrator of one company may not rebrand another.',
        );
    }
}
