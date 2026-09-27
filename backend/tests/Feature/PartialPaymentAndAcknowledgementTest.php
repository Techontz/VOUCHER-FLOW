<?php

namespace Tests\Feature;

use App\Models\Voucher;
use App\Models\VoucherPayment;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Money released in parts (10,000,000 approved, 9,000,000 paid now, the rest
 * later), and the acknowledgement each receiver signs for what they took.
 */
class PartialPaymentAndAcknowledgementTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private const SIGNATURE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    private function approvedCash(array $t, float $amount = 10000000): Voucher
    {
        $voucher = $this->makeVoucher($t, null, $amount);
        $voucher->forceFill(['kind' => Voucher::KIND_CASH])->save();

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE])->assertOk();
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed")->assertOk();
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve")->assertOk();

        return $voucher->fresh();
    }

    public function test_a_voucher_is_paid_in_two_parts(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->approvedCash($t);

        // 9,000,000 now.
        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['amount' => 9000000, 'received_by' => 'Juma Hassan', 'receiver_id_number' => 'EMP-0042'])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_APPROVED)
            ->assertJsonPath('data.status_key', 'partially_paid')
            ->assertJsonPath('data.amount_paid', 9000000)
            ->assertJsonPath('data.balance', 1000000)
            ->assertJsonPath('data.actions.pay', true)
            ->assertJsonPath('data.payments.0.amount', 9000000)
            ->assertJsonPath('data.payments.0.balance_after', 1000000)
            ->assertJsonPath('data.payments.0.received_by', 'Juma Hassan');

        $this->assertNull($voucher->fresh()->paid_at);

        // More than the balance is refused.
        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['amount' => 1500000, 'received_by' => 'Juma Hassan'])
            ->assertStatus(422);

        // The balance later; leaving the amount out pays whatever is owed.
        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['received_by' => 'Juma Hassan'])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_PAID)
            ->assertJsonPath('data.balance', 0)
            ->assertJsonPath('data.payments.1.sequence', 2)
            ->assertJsonPath('data.payments.1.amount', 1000000);

        $this->assertSame(2, VoucherPayment::count());
        $actions = $voucher->fresh()->approvals()->pluck('action')->all();
        $this->assertContains('part_paid', $actions);
        $this->assertContains('paid', $actions);

        // Nothing more can be paid.
        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['received_by' => 'Juma Hassan'])
            ->assertStatus(422);
    }

    public function test_a_single_full_payment_still_works_as_before(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->approvedCash($t, 250000);

        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['received_by' => 'Asha Said'])
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_PAID)
            ->assertJsonPath('data.status_key', 'paid')
            ->assertJsonPath('data.payments.0.amount', 250000);
    }

    public function test_each_payment_has_a_printable_acknowledgement(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->approvedCash($t);
        $payment = $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['amount' => 9000000, 'received_by' => 'Juma Hassan'])
            ->json('data.payments.0');

        $response = $this->actingAs($t['cashier'], 'sanctum')
            ->get("/api/vouchers/{$voucher->id}/payments/{$payment['id']}/acknowledgement");

        $response->assertOk();
        $this->assertSame('application/pdf', $response->headers->get('content-type'));

        // Swahili too.
        $this->actingAs($t['cashier'], 'sanctum')
            ->get("/api/vouchers/{$voucher->id}/payments/{$payment['id']}/acknowledgement?lang=sw")
            ->assertOk();
    }

    public function test_the_cashier_files_the_signed_acknowledgement_on_the_voucher(): void
    {
        Storage::fake('local');
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->approvedCash($t);
        $payment = $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['amount' => 9000000, 'received_by' => 'Juma Hassan'])
            ->json('data.payments.0');

        $this->actingAs($t['cashier'], 'sanctum')
            ->post("/api/vouchers/{$voucher->id}/payments/{$payment['id']}/acknowledgement", [
                'file' => UploadedFile::fake()->image('signed.jpg'),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('data.payments.0.acknowledged_at', fn ($v) => $v !== null)
            ->assertJsonPath('data.attachments.0.document_type', 'payment_acknowledgement')
            ->assertJsonPath('data.attachments.0.voucher_payment_id', $payment['id']);

        $this->assertTrue($voucher->fresh()->approvals()->where('action', 'acknowledged')->exists());
    }

    public function test_only_the_cashier_or_an_admin_files_the_acknowledgement(): void
    {
        Storage::fake('local');
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->approvedCash($t);
        $payment = $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['amount' => 9000000, 'received_by' => 'Juma Hassan'])
            ->json('data.payments.0');

        $this->actingAs($t['employee'], 'sanctum')
            ->post("/api/vouchers/{$voucher->id}/payments/{$payment['id']}/acknowledgement", [
                'file' => UploadedFile::fake()->image('signed.jpg'),
            ], ['Accept' => 'application/json'])
            ->assertForbidden();

        $this->actingAs($t['admin'], 'sanctum')
            ->post("/api/vouchers/{$voucher->id}/payments/{$payment['id']}/acknowledgement", [
                'file' => UploadedFile::fake()->image('signed.jpg'),
            ], ['Accept' => 'application/json'])
            ->assertCreated();
    }

    public function test_another_company_cannot_print_or_file_an_acknowledgement(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $other = $this->makeTenant('Beta Supplies');
        $voucher = $this->approvedCash($t);
        $payment = $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['amount' => 9000000, 'received_by' => 'Juma Hassan'])
            ->json('data.payments.0');

        $this->actingAs($other['cashier'], 'sanctum')
            ->get("/api/vouchers/{$voucher->id}/payments/{$payment['id']}/acknowledgement", ['Accept' => 'application/json'])
            ->assertNotFound();
    }

    public function test_the_cashier_dashboard_counts_the_balance_owed_and_the_money_released(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->approvedCash($t);
        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['amount' => 9000000, 'received_by' => 'Juma Hassan'])
            ->assertOk();

        $stats = collect($this->actingAs($t['cashier'], 'sanctum')->getJson('/api/dashboard')->json('data.stats'))->keyBy('key');

        $this->assertStringContainsString('1,000,000', $stats['dash.stat.pendingPayments']['value']);
        $this->assertStringContainsString('9,000,000', $stats['dash.stat.paidThisMonth']['value']);
    }
}
