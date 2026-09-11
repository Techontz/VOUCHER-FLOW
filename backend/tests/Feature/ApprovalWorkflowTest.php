<?php

namespace Tests\Feature;

use App\Models\Voucher;
use App\Models\Workflow;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * The product rule the design is built around: a signing step signs and then
 * hands the voucher on. It never approves.
 */
class ApprovalWorkflowTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private const SIGNATURE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    public function test_the_full_route_from_draft_to_paid(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($t);

        // Submit.
        $this->actingAs($t['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/submit")
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_IN_REVIEW)
            ->assertJsonPath('data.status_key', 'awaiting_signature');

        // The HOD may sign but must not be offered approval.
        $detail = $this->actingAs($t['hod'], 'sanctum')
            ->getJson("/api/vouchers/{$voucher->id}")->assertOk();

        $this->assertTrue($detail->json('data.actions.sign'));
        $this->assertFalse($detail->json('data.actions.approve'));

        // And the API refuses it even if asked directly.
        $this->actingAs($t['hod'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/approve", ['comment' => 'trying'])
            ->assertStatus(422);

        // Signing does not approve.
        $this->actingAs($t['hod'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_IN_REVIEW)
            ->assertJsonPath('data.status_key', 'signed_pending_submit')
            ->assertJsonPath('data.actions.submit_signed', true);

        // Signing twice at the same step is refused.
        $this->actingAs($t['hod'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE])
            ->assertStatus(422);

        // Hand it onward.
        $this->actingAs($t['hod'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/submit-signed")
            ->assertOk()
            ->assertJsonPath('data.status_key', 'awaiting_approval');

        // Only the CEO step decides.
        $this->actingAs($t['ceo'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/approve", ['comment' => 'Cleared.'])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_APPROVED)
            ->assertJsonPath('data.status_key', 'awaiting_payment');

        $this->assertNotNull($voucher->fresh()->approved_at);

        // Approval is not the end: the money still has to move, and only the
        // step carrying `can_pay` may move it.
        $this->actingAs($t['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['payment_reference' => 'TRX-1'])
            ->assertStatus(422);

        $this->actingAs($t['cashier'], 'sanctum')
            ->getJson("/api/vouchers/{$voucher->id}")
            ->assertJsonPath('data.actions.pay', true);

        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", [
                'payment_reference' => 'CRDB-TRX-99812',
                'payment_method' => 'Bank Transfer',
            ])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_PAID)
            ->assertJsonPath('data.status_key', 'paid')
            ->assertJsonPath('data.payment_reference', 'CRDB-TRX-99812');

        $paid = $voucher->fresh();
        $this->assertNotNull($paid->paid_at);
        $this->assertSame($t['cashier']->id, $paid->paid_by_id);

        // And it cannot be paid twice.
        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['payment_reference' => 'CRDB-TRX-99813'])
            ->assertStatus(422);
    }

    /**
     * A cash voucher asks for a different acknowledgement: no transfer
     * reference exists, but somebody physically took the notes.
     */
    public function test_a_cash_voucher_records_who_received_the_money(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($t);
        $voucher->forceFill(['kind' => Voucher::KIND_CASH])->save();

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit");
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE]);
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed");
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve");

        // A bank reference is meaningless here; the recipient's name is not.
        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['payment_method' => 'Cash'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('received_by');

        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", [
                'payment_method' => 'Cash',
                'received_by' => 'Frank Kessy',
            ])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_PAID)
            ->assertJsonPath('data.received_by', 'Frank Kessy');
    }

    public function test_the_approving_step_can_reject_and_the_voucher_closes(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit");
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE]);
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed");

        $this->actingAs($t['ceo'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/reject", ['comment' => 'Use the branch float.'])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_REJECTED);

        // A rejection needs a reason on the record.
        $second = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$second->id}/submit");
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$second->id}/sign", ['signature' => self::SIGNATURE]);
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$second->id}/submit-signed");

        $this->actingAs($t['ceo'], 'sanctum')
            ->postJson("/api/vouchers/{$second->id}/reject", ['comment' => ''])
            ->assertStatus(422);
    }

    public function test_requesting_changes_returns_the_voucher_to_its_author(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit");

        $this->actingAs($t['hod'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/request-changes", ['comment' => 'Attach the invoice.'])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_CHANGES_REQUESTED);

        // Editable again, and re-submittable.
        $this->actingAs($t['employee'], 'sanctum')
            ->getJson("/api/vouchers/{$voucher->id}")
            ->assertJsonPath('data.actions.edit', true);

        $this->actingAs($t['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/submit")
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_IN_REVIEW);
    }

    /**
     * A tenant whose route puts Finance between the HOD and the Manager must
     * route through all four steps — no code change, only configuration.
     */
    public function test_a_four_step_route_is_honoured(): void
    {
        $t = $this->makeTenant('Zamani Freight', preset: 'finance');
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();

        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE])->assertOk();
        $this->actingAs($t['hod'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/submit-signed")
            ->assertOk()
            ->assertJsonPath('data.current_step_position', 3);

        // The manager's step has not been reached yet.
        $this->actingAs($t['manager'], 'sanctum')
            ->getJson("/api/vouchers/{$voucher->id}")
            ->assertJsonPath('data.actions.approve', false);

        // Finance approves and the voucher advances rather than completing.
        $this->actingAs($t['finance'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/approve", ['comment' => 'Verified.'])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_IN_REVIEW)
            ->assertJsonPath('data.current_step_position', 4);

        $this->actingAs($t['manager'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/approve")
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_APPROVED);

        // This tenant pays from its finance step rather than a cashier — the
        // capability travels with the step, not with the job title.
        $this->actingAs($t['finance'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['payment_reference' => 'NMB-77120'])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_PAID);
    }

    public function test_a_single_approver_route_completes_in_one_decision(): void
    {
        $t = $this->makeTenant('Baobab Solutions', preset: 'single');
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();

        $this->actingAs($t['manager'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/approve", ['signature' => self::SIGNATURE])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_APPROVED);
    }

    public function test_the_timeline_is_built_from_the_configured_workflow(): void
    {
        $t = $this->makeTenant('Zamani Freight', preset: 'finance');
        $voucher = $this->makeVoucher($t);

        $timeline = $this->actingAs($t['admin'], 'sanctum')
            ->getJson("/api/vouchers/{$voucher->id}")
            ->json('data.timeline');

        // Five configured steps plus the closing "Completed" row.
        $this->assertCount(6, $timeline);
        $this->assertSame('Finance verification', $timeline[2]['name']);
    }

    public function test_an_administrator_can_reshape_the_route(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $workflow = app(TenantContext::class)->forCompany(
            $t['company'],
            fn () => Workflow::with('steps')->where('is_default', true)->firstOrFail(),
        );

        $steps = $workflow->steps->map(fn ($step) => [
            'id' => $step->id,
            'name' => $step->name,
            'role' => $step->role,
            'can_sign' => $step->can_sign,
            'can_approve' => $step->can_approve,
            'can_reject' => $step->can_reject,
            'can_request_changes' => $step->can_request_changes,
            'can_print' => true,
            // Carried through deliberately: a PUT replaces the route, so a
            // capability left out of the payload is a capability taken away.
            'can_pay' => $step->can_pay,
        ])->all();

        // Insert a Finance gate before management approval.
        array_splice($steps, 2, 0, [[
            'name' => 'Finance check', 'role' => 'finance',
            'can_sign' => false, 'can_approve' => true, 'can_reject' => true,
            'can_request_changes' => false, 'can_print' => true,
        ]]);

        $this->actingAs($t['admin'], 'sanctum')
            ->putJson("/api/workflows/{$workflow->id}", [
                'name' => $workflow->name,
                'is_default' => true,
                'is_active' => true,
                'steps' => $steps,
            ])
            ->assertOk()
            ->assertJsonCount(5, 'data.steps');

        // A non-administrator may not.
        $this->actingAs($t['employee'], 'sanctum')
            ->postJson('/api/workflows/apply-preset', ['preset' => 'single'])
            ->assertForbidden();
    }
}
