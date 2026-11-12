<?php

namespace Tests\Feature;

use App\Models\Erp\Account;
use App\Models\Erp\JournalEntry;
use App\Models\Erp\JournalLine;
use App\Models\Erp\Procurement\ProcurementSetting;
use App\Models\Erp\Procurement\SupplierPayment;
use App\Models\User;
use App\Models\Voucher;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * VouchFlow and the books (acceptance 9, 11 and 12 end to end): a supplier
 * invoice raises a payment voucher, the voucher follows the company's own
 * route (HOD signs, CEO approves), and the cashier's payment clears the
 * invoice and posts to the ledger exactly once.
 */
class ErpVoucherLinkTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private const SIGNATURE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

    /** A tenant with a posted supplier invoice of TZS 354,000 waiting to be paid. */
    private function invoiced(string $name = 'Maji Bora'): array
    {
        $erp = $this->setUpErp($this->makeTenant($name));
        $erp['finance']->forceFill(['department_id' => $erp['department']->id])->save();

        app(TenantContext::class)->forCompany($erp['company'], function () use (&$erp) {
            ProcurementSetting::current()->update(['approval_threshold' => 50000000, 'price_tolerance_percent' => 2, 'receipt_tolerance_percent' => 0]);
            $slug = $erp['company']->slug;
            $erp['officer'] = User::create([
                'company_id' => $erp['company']->id, 'name' => "Officer {$slug}", 'email' => "officer@{$slug}.test",
                'password' => 'Password123!', 'role' => User::ROLE_PROCUREMENT, 'status' => 'active',
            ]);
        });

        $as = fn (string $who) => $this->actingAs($erp[$who], 'sanctum');

        $order = $as('officer')->postJson('/api/erp/procurement/orders', [
            'supplier_id' => $erp['supplier']->id, 'warehouse_id' => $erp['main']->id,
            'lines' => [['line_type' => 'stock', 'product_id' => $erp['product']->id, 'quantity' => 50, 'unit_price' => 6000, 'vat_rate' => 18]],
        ])->assertCreated()->json('data');
        $as('officer')->postJson("/api/erp/procurement/orders/{$order['id']}/submit")->assertOk();
        $as('finance')->postJson("/api/erp/procurement/orders/{$order['id']}/approve")->assertOk();
        $as('officer')->postJson("/api/erp/procurement/orders/{$order['id']}/send")->assertOk();
        $order = $this->getJson("/api/erp/procurement/orders/{$order['id']}")->json('data');

        $as('storekeeper')->postJson("/api/erp/procurement/orders/{$order['id']}/receive", [
            'delivery_note' => 'DN-1001', 'warehouse_id' => $erp['main']->id,
            'lines' => [['purchase_order_line_id' => $order['lines'][0]['id'], 'quantity' => 50]],
        ])->assertCreated();

        $invoice = $as('accountant')->postJson('/api/erp/procurement/invoices', [
            'purchase_order_id' => $order['id'], 'supplier_invoice_number' => 'INV-7781', 'invoice_date' => now()->toDateString(),
            'lines' => [['purchase_order_line_id' => $order['lines'][0]['id'], 'quantity' => 50, 'unit_price' => 6000]],
        ])->assertCreated()->json('data');
        $as('accountant')->postJson("/api/erp/procurement/invoices/{$invoice['id']}/post")->assertOk();

        return [...$erp, 'invoice' => $invoice];
    }

    /** Submit, sign, forward and approve: the company's own route. */
    private function approve(array $erp, int $voucherId): void
    {
        $this->actingAs($erp['finance'], 'sanctum')->postJson("/api/vouchers/{$voucherId}/submit")->assertOk();
        $this->actingAs($erp['hod'], 'sanctum')->postJson("/api/vouchers/{$voucherId}/sign", ['signature' => self::SIGNATURE])->assertOk();
        $this->actingAs($erp['hod'], 'sanctum')->postJson("/api/vouchers/{$voucherId}/submit-signed")->assertOk();
        $this->actingAs($erp['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucherId}/approve", ['comment' => 'Pay it.'])
            ->assertOk()->assertJsonPath('data.status', Voucher::STATUS_APPROVED);
    }

    /** @return array<string, float> system key => net debit, for every journal keyed to $type */
    private function postedBy(string $type): array
    {
        $ids = JournalEntry::acrossTenants()->where('source_type', $type)->pluck('id');
        $lines = JournalLine::query()->whereIn('journal_entry_id', $ids)->get();
        $this->assertSame((int) round($lines->sum('debit') * 100), (int) round($lines->sum('credit') * 100));
        $accounts = Account::acrossTenants()->whereIn('id', $lines->pluck('account_id'))->get()->keyBy('id');

        $net = [];
        foreach ($lines as $line) {
            $key = $accounts[$line->account_id]->system_key ?? $accounts[$line->account_id]->code;
            $net[$key] = round(($net[$key] ?? 0) + (float) $line->debit - (float) $line->credit, 2);
        }

        return $net;
    }

    public function test_a_supplier_invoice_is_paid_through_the_voucher_route_and_posted_once(): void
    {
        $erp = $this->invoiced();
        $invoiceId = $erp['invoice']['id'];

        $voucher = $this->actingAs($erp['finance'], 'sanctum')
            ->postJson("/api/erp/procurement/invoices/{$invoiceId}/voucher")
            ->assertCreated()->json('data');

        // One voucher at a time per invoice.
        $this->actingAs($erp['finance'], 'sanctum')->postJson("/api/erp/procurement/invoices/{$invoiceId}/voucher")
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, $voucher['number']));
        $this->getJson("/api/erp/procurement/invoices/{$invoiceId}/voucher")->assertJsonPath('data.number', $voucher['number']);

        $this->actingAs($erp['finance'], 'sanctum')->getJson("/api/vouchers/{$voucher['id']}")
            ->assertOk()
            ->assertJsonPath('data.amount', fn ($a) => (float) $a === 354000.0)
            ->assertJsonPath('data.source.type', 'supplier_invoice')
            ->assertJsonPath('data.source.id', $invoiceId);

        // Approval alone moves no money and posts nothing.
        $this->approve($erp, $voucher['id']);
        $this->assertSame(0, SupplierPayment::acrossTenants()->count());

        // The cashier pays part, then the rest: each release clears the invoice in step.
        $this->actingAs($erp['cashier'], 'sanctum')->postJson("/api/vouchers/{$voucher['id']}/pay", [
            'amount' => 154000, 'payment_reference' => 'CRDB-1', 'payment_method' => 'Bank Transfer',
        ])->assertOk();
        $this->getJson("/api/erp/procurement/invoices/{$invoiceId}")->assertJsonPath('data.payment_status', 'partially_paid');

        $this->actingAs($erp['cashier'], 'sanctum')->postJson("/api/vouchers/{$voucher['id']}/pay", [
            'payment_reference' => 'CRDB-2', 'payment_method' => 'Bank Transfer',
        ])->assertOk()->assertJsonPath('data.status', Voucher::STATUS_PAID);

        $this->getJson("/api/erp/procurement/invoices/{$invoiceId}")
            ->assertJsonPath('data.payment_status', 'paid')->assertJsonPath('data.outstanding', 0);
        $this->assertSame(2, SupplierPayment::acrossTenants()->where('status', 'posted')->count());
        $this->assertSame(['payable' => 354000.0, 'bank' => -354000.0], $this->postedBy('SupplierPayment'));

        // Paid in full: it cannot be paid again, and no new voucher can be raised.
        $this->actingAs($erp['cashier'], 'sanctum')->postJson("/api/vouchers/{$voucher['id']}/pay", ['payment_reference' => 'CRDB-3'])->assertStatus(422);
        $this->actingAs($erp['finance'], 'sanctum')->postJson("/api/erp/procurement/invoices/{$invoiceId}/voucher")->assertStatus(422);
    }

    public function test_a_rejected_voucher_is_never_paid_and_the_invoice_can_raise_another(): void
    {
        $erp = $this->invoiced();
        $invoiceId = $erp['invoice']['id'];
        $voucher = $this->actingAs($erp['finance'], 'sanctum')->postJson("/api/erp/procurement/invoices/{$invoiceId}/voucher")->json('data');

        $this->actingAs($erp['finance'], 'sanctum')->postJson("/api/vouchers/{$voucher['id']}/submit")->assertOk();
        $this->actingAs($erp['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher['id']}/sign", ['signature' => self::SIGNATURE])->assertOk();
        $this->actingAs($erp['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher['id']}/submit-signed")->assertOk();
        $this->actingAs($erp['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher['id']}/reject", ['comment' => 'Wrong supplier account.'])->assertOk();

        $this->actingAs($erp['cashier'], 'sanctum')->postJson("/api/vouchers/{$voucher['id']}/pay", ['payment_reference' => 'X'])->assertStatus(422);
        $this->assertSame(0, SupplierPayment::acrossTenants()->count());

        $this->actingAs($erp['finance'], 'sanctum')->postJson("/api/erp/procurement/invoices/{$invoiceId}/voucher")->assertCreated();
    }

    public function test_a_voucher_coded_to_an_account_posts_its_payment_once(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Coded Co'));
        $rent = app(TenantContext::class)->forCompany($erp['company'], fn () => Account::where('system_key', 'rent')->value('id'));
        $voucher = $this->makeVoucher($erp, $erp['employee'], 1200000);
        $voucher->forceFill(['ledger_account_id' => $rent])->save();

        $this->actingAs($erp['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();
        $this->actingAs($erp['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE])->assertOk();
        $this->actingAs($erp['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed")->assertOk();
        $this->actingAs($erp['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve", ['comment' => 'Ok'])->assertOk();
        $this->actingAs($erp['cashier'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/pay", ['payment_reference' => 'NMB-9', 'payment_method' => 'Bank Transfer'])
            ->assertOk()->assertJsonPath('data.status', Voucher::STATUS_PAID);

        $this->assertSame(['rent' => 1200000.0, 'bank' => -1200000.0], $this->postedBy('VoucherPayment'));
        $this->assertSame(1, JournalEntry::acrossTenants()->where('source_type', 'VoucherPayment')->count());
    }

    public function test_another_companys_invoice_cannot_raise_a_voucher_here(): void
    {
        $ours = $this->invoiced('Ours Ltd');
        $theirs = $this->setUpErp($this->makeTenant('Theirs Ltd'));

        $this->actingAs($theirs['finance'], 'sanctum')
            ->postJson("/api/erp/procurement/invoices/{$ours['invoice']['id']}/voucher")->assertNotFound();
        $this->actingAs($ours['employee'], 'sanctum')
            ->postJson("/api/erp/procurement/invoices/{$ours['invoice']['id']}/voucher")->assertForbidden();
    }
}
