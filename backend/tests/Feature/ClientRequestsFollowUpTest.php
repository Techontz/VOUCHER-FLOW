<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\User;
use App\Models\Voucher;
use App\Notifications\VoucherReminderNotification;
use App\Services\VoucherReminders;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * The client's follow-up requests: bulk approval for the CEO, attachments that
 * stay open after payment, and a reminder once a voucher waits 24 hours.
 */
class ClientRequestsFollowUpTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private const SIGNATURE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /** Submitted, signed by the HOD and forwarded: waiting on the CEO. */
    private function atCeo(array $t, float $amount = 250000): Voucher
    {
        $voucher = $this->makeVoucher($t, null, $amount);
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE])->assertOk();
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed")->assertOk();

        return $voucher->fresh();
    }

    private function paid(array $t): Voucher
    {
        $voucher = $this->atCeo($t);
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve")->assertOk();
        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['payment_reference' => 'TRX-1'])
            ->assertOk();

        return $voucher->fresh();
    }

    /* ─────────────────────────────── bulk approve ─────────────────────── */

    public function test_the_ceo_approves_several_vouchers_in_one_action(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['ceo']->forceFill(['signature_data' => self::SIGNATURE])->save();
        $a = $this->atCeo($t);
        $b = $this->atCeo($t, 480000);

        $this->actingAs($t['ceo'], 'sanctum')
            ->postJson('/api/vouchers/bulk-approve', ['ids' => [$a->id, $b->id], 'confirm' => true, 'comment' => 'Reviewed.'])
            ->assertOk()
            ->assertJsonCount(2, 'approved')
            ->assertJsonCount(0, 'skipped');

        $this->assertSame(Voucher::STATUS_APPROVED, $a->fresh()->status);
        $this->assertSame(Voucher::STATUS_APPROVED, $b->fresh()->status);

        // The same timeline entry a single approval writes.
        $this->assertTrue($a->fresh()->approvals()->where('action', 'approved')->where('actor_id', $t['ceo']->id)->exists());
    }

    public function test_bulk_approval_must_be_confirmed(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $a = $this->atCeo($t);

        $this->actingAs($t['ceo'], 'sanctum')
            ->postJson('/api/vouchers/bulk-approve', ['ids' => [$a->id]])
            ->assertStatus(422)
            ->assertJsonValidationErrors('confirm');

        $this->assertSame(Voucher::STATUS_IN_REVIEW, $a->fresh()->status);
    }

    public function test_bulk_approval_skips_what_the_caller_may_not_approve(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $other = $this->makeTenant('Beta Supplies');
        $atCeo = $this->atCeo($t);

        // Still at the HOD's signature step.
        $atHod = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$atHod->id}/submit")->assertOk();

        // Another company's voucher.
        $foreign = app(TenantContext::class)->forCompany($other['company'], fn () => $this->atCeo($other));

        $response = $this->actingAs($t['ceo'], 'sanctum')
            ->postJson('/api/vouchers/bulk-approve', ['ids' => [$atCeo->id, $atHod->id, $foreign->id], 'confirm' => true])
            ->assertOk()
            ->assertJsonCount(1, 'approved')
            ->assertJsonCount(2, 'skipped');

        $this->assertSame($atCeo->id, $response->json('approved.0.id'));
        $this->assertSame(Voucher::STATUS_IN_REVIEW, $atHod->fresh()->status);
        $this->assertSame(Voucher::STATUS_IN_REVIEW, Voucher::acrossTenants()->find($foreign->id)->status);
    }

    public function test_the_hod_cannot_bulk_approve_what_they_only_sign(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['hod']->forceFill(['signature_data' => self::SIGNATURE])->save();
        $voucher = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();

        $this->actingAs($t['hod'], 'sanctum')
            ->postJson('/api/vouchers/bulk-approve', ['ids' => [$voucher->id], 'confirm' => true])
            ->assertOk()
            ->assertJsonCount(0, 'approved');

        $this->assertNull($voucher->fresh()->approved_at);
    }

    /* ───────────────────────── attachments after payment ───────────────── */

    public function test_the_requester_and_cashier_can_attach_a_receipt_after_payment(): void
    {
        Storage::fake('local');
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->paid($t);

        foreach (['employee', 'cashier'] as $who) {
            $this->actingAs($t[$who], 'sanctum')
                ->post("/api/vouchers/{$voucher->id}/attachments", [
                    'files' => [UploadedFile::fake()->create("receipt-{$who}.pdf", 20, 'application/pdf')],
                ], ['Accept' => 'application/json'])
                ->assertCreated();
        }

        $this->assertSame(2, $voucher->attachments()->count());
        $this->assertTrue($this->actingAs($t['employee'], 'sanctum')->getJson("/api/vouchers/{$voucher->id}")->json('data.actions.attach'));
    }

    public function test_an_uninvolved_colleague_cannot_attach_after_payment(): void
    {
        Storage::fake('local');
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->paid($t);

        $this->actingAs($t['hod'], 'sanctum')
            ->post("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('receipt.pdf', 20, 'application/pdf')],
            ], ['Accept' => 'application/json'])
            ->assertForbidden();
    }

    public function test_approved_evidence_stays_but_a_later_receipt_can_be_withdrawn_by_its_uploader(): void
    {
        Storage::fake('local');
        $t = $this->makeTenant('Acme Trading');

        $voucher = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')
            ->post("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('invoice.pdf', 20, 'application/pdf')],
            ], ['Accept' => 'application/json'])->assertCreated();
        $original = $voucher->attachments()->first();

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE])->assertOk();
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed")->assertOk();
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve")->assertOk();
        $this->actingAs($t['cashier'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/pay", ['payment_reference' => 'TRX-9'])->assertOk();

        $this->travel(1)->minutes();
        $receipt = $this->actingAs($t['cashier'], 'sanctum')
            ->post("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('receipt.pdf', 20, 'application/pdf')],
            ], ['Accept' => 'application/json'])->assertCreated()->json('data.0.id');

        $this->actingAs($t['employee'], 'sanctum')
            ->deleteJson("/api/vouchers/{$voucher->id}/attachments/{$original->id}")
            ->assertForbidden();

        $this->actingAs($t['cashier'], 'sanctum')
            ->deleteJson("/api/vouchers/{$voucher->id}/attachments/{$receipt}")
            ->assertOk();
    }

    /* ──────────────────────────────── reminders ───────────────────────── */

    public function test_whoever_holds_a_voucher_is_reminded_after_24_hours_once_a_day(): void
    {
        Notification::fake();
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();

        $run = fn () => app(VoucherReminders::class)->run();
        $reminders = fn (User $u) => AppNotification::where('user_id', $u->id)->where('type', VoucherReminders::TYPE)->count();

        // Not yet a day.
        $this->travel(23)->hours();
        $run();
        $this->assertSame(0, $reminders($t['hod']));

        // A day: the HOD, who must sign, is reminded — in-app and by email.
        $this->travel(2)->hours();
        $run();
        $this->assertSame(1, $reminders($t['hod']));
        Notification::assertSentTo($t['hod'], VoucherReminderNotification::class);
        $this->assertStringContainsString('waiting for your signature', AppNotification::where('user_id', $t['hod']->id)->where('type', VoucherReminders::TYPE)->first()->title);

        // The next hourly run doesn't repeat it; the next day does.
        $this->travel(1)->hours();
        $run();
        $this->assertSame(1, $reminders($t['hod']));
        $this->travel(24)->hours();
        $run();
        $this->assertSame(2, $reminders($t['hod']));

        // Nobody else is reminded about a voucher they are not holding.
        $this->assertSame(0, $reminders($t['ceo']));
        $this->assertSame(0, $reminders($t['employee']));
    }

    public function test_the_cashier_is_reminded_about_an_approved_voucher_left_unpaid(): void
    {
        Notification::fake();
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->atCeo($t);
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve")->assertOk();

        $this->travel(25)->hours();
        app(VoucherReminders::class)->run();

        $note = AppNotification::where('user_id', $t['cashier']->id)->where('type', VoucherReminders::TYPE)->first();
        $this->assertNotNull($note);
        $this->assertStringContainsString('waiting for payment', $note->title);
    }

    public function test_a_voucher_sent_back_reminds_its_requester_and_other_companies_are_untouched(): void
    {
        Notification::fake();
        $t = $this->makeTenant('Acme Trading');
        $other = $this->makeTenant('Beta Supplies');
        $voucher = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/request-changes", ['comment' => 'Attach the invoice.'])->assertOk();

        $this->travel(25)->hours();
        app(VoucherReminders::class)->run();

        $this->assertSame(1, AppNotification::where('user_id', $t['employee']->id)->where('type', VoucherReminders::TYPE)->count());
        $this->assertSame(0, AppNotification::withoutGlobalScopes()->where('company_id', $other['company']->id)->where('type', VoucherReminders::TYPE)->count());
    }

    public function test_the_reminder_command_runs(): void
    {
        $this->artisan('vouchers:remind')->assertSuccessful();
    }
}
