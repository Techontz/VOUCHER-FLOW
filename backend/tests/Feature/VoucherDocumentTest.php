<?php

namespace Tests\Feature;

use App\Models\Voucher;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * The printed voucher is the artefact the business actually files, so it gets
 * the same scrutiny as the workflow that produced it.
 */
class VoucherDocumentTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private const SIGNATURE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    private function runToPaid(array $t, Voucher $voucher): Voucher
    {
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit");
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE]);
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed");
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve");

        $this->actingAs($t['cashier'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/pay", $voucher->isBank()
            ? ['payment_reference' => 'CRDB-TRX-1234']
            : ['received_by' => 'Somebody', 'payment_method' => 'Cash']);

        return $voucher->fresh();
    }

    public function test_a_paid_voucher_renders_as_a_single_page_pdf(): void
    {
        $t = $this->makeTenant('Watercom Demo');
        $voucher = $this->runToPaid($t, $this->makeVoucher($t));

        $response = $this->actingAs($t['cashier'], 'sanctum')
            ->get("/api/vouchers/{$voucher->id}/pdf")
            ->assertOk();

        $pdf = $response->getContent();

        $this->assertStringStartsWith('%PDF', $pdf);
        $this->assertSame(
            1,
            preg_match_all('#/Type\s*/Page[^s]#', $pdf),
            'A voucher must print on one page.',
        );
    }

    /**
     * The regression this guards: removing "approved" from isTerminal() also
     * removed the print grant from every approved voucher, so the cashier
     * could not print the document they were about to pay against.
     */
    public function test_an_approved_voucher_can_still_be_printed_by_whoever_must_pay_it(): void
    {
        $t = $this->makeTenant('Watercom Demo');
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit");
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE]);
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed");
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve");

        $this->assertSame(Voucher::STATUS_APPROVED, $voucher->fresh()->status);

        $this->actingAs($t['cashier'], 'sanctum')
            ->getJson("/api/vouchers/{$voucher->id}")
            ->assertJsonPath('data.actions.print', true)
            ->assertJsonPath('data.actions.download', true);

        $this->actingAs($t['cashier'], 'sanctum')
            ->get("/api/vouchers/{$voucher->id}/pdf")
            ->assertOk();
    }

    /**
     * 404 rather than 403 is deliberate: route-model binding resolves inside the
     * tenant scope, so another company's voucher does not exist as far as this
     * caller is concerned. Answering "forbidden" would confirm that it does.
     */
    public function test_the_document_is_refused_across_a_company_boundary(): void
    {
        $mine = $this->makeTenant('Watercom Demo');
        $theirs = $this->makeTenant('Zamani Freight');

        $foreign = $this->makeVoucher($theirs);

        $this->actingAs($mine['admin'], 'sanctum')
            ->get("/api/vouchers/{$foreign->id}/pdf")
            ->assertNotFound();
    }

    public function test_a_cash_voucher_prints_cash_particulars_and_a_bank_voucher_prints_bank_ones(): void
    {
        $t = $this->makeTenant('Watercom Demo');

        $bank = $this->makeVoucher($t);
        $bank->forceFill([
            'kind' => Voucher::KIND_BANK,
            'payee_bank' => 'NMB Bank',
            'payee_account_number' => '20110034877',
        ])->save();

        $cash = $this->makeVoucher($t);
        $cash->forceFill(['kind' => Voucher::KIND_CASH, 'cash_float' => 'Head office petty cash'])->save();

        // The API resource carries only the particulars that format uses, so a
        // client never renders an empty "Branch" row on a cash claim.
        $bankJson = $this->actingAs($t['admin'], 'sanctum')->getJson("/api/vouchers/{$bank->id}")->json('data');
        $cashJson = $this->actingAs($t['admin'], 'sanctum')->getJson("/api/vouchers/{$cash->id}")->json('data');

        $this->assertSame('NMB Bank', $bankJson['payee_bank']);
        $this->assertArrayNotHasKey('cash_float', $bankJson);

        $this->assertSame('Head office petty cash', $cashJson['cash_float']);
        $this->assertArrayNotHasKey('payee_bank', $cashJson);
    }
}
