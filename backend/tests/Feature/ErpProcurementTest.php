<?php

namespace Tests\Feature;

use App\Models\Erp\Account;
use App\Models\Erp\JournalEntry;
use App\Models\Erp\JournalLine;
use App\Models\Erp\Procurement\ProcurementApproval;
use App\Models\Erp\Procurement\ProcurementSetting;
use App\Models\Erp\StockBalance;
use App\Models\Erp\StockDocument;
use App\Models\Erp\Supplier;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * The procurement cycle: requisition approval by amount, quotations compared,
 * orders received through the core GRN, invoices matched three ways and
 * posted once, payments posted once. Acceptance criterion 9 lives here.
 */
class ErpProcurementTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function erp(string $name = 'Maji Bora'): array
    {
        $erp = $this->setUpErp($this->makeTenant($name));

        return app(TenantContext::class)->forCompany($erp['company'], function () use ($erp) {
            $slug = $erp['company']->slug;
            ProcurementSetting::current()->update(['approval_threshold' => 5000000, 'price_tolerance_percent' => 2, 'receipt_tolerance_percent' => 0]);

            return [...$erp, 'officer' => User::create([
                'company_id' => $erp['company']->id, 'name' => "Officer {$slug}", 'email' => "officer@{$slug}.test",
                'password' => 'Password123!', 'role' => User::ROLE_PROCUREMENT, 'status' => 'active',
            ])];
        });
    }

    private function as(array $erp, string $who): static
    {
        return $this->actingAs($erp[$who], 'sanctum');
    }

    private function requisition(array $erp, float $quantity, float $price, string $as = 'officer'): TestResponse
    {
        return $this->as($erp, $as)->postJson('/api/erp/procurement/requisitions', [
            'justification' => 'Stock for the coming week',
            'needed_by' => now()->addWeek()->toDateString(),
            'lines' => [['line_type' => 'stock', 'product_id' => $erp['product']->id, 'quantity' => $quantity, 'estimated_unit_price' => $price]],
        ]);
    }

    /** An approved and sent order for the given lines, ready to receive. */
    private function sentOrder(array $erp, array $lines): array
    {
        $order = $this->as($erp, 'officer')->postJson('/api/erp/procurement/orders', [
            'supplier_id' => $erp['supplier']->id,
            'warehouse_id' => $erp['main']->id,
            'lines' => $lines,
        ])->assertCreated()->json('data');

        $this->as($erp, 'officer')->postJson("/api/erp/procurement/orders/{$order['id']}/submit")->assertOk();
        $this->as($erp, 'finance')->postJson("/api/erp/procurement/orders/{$order['id']}/approve")->assertOk()->assertJsonPath('data.status', 'approved');
        $this->as($erp, 'officer')->postJson("/api/erp/procurement/orders/{$order['id']}/send")->assertOk()->assertJsonPath('data.status', 'sent');

        return $this->getJson("/api/erp/procurement/orders/{$order['id']}")->json('data');
    }

    private function stockLine(array $erp, float $quantity, float $price = 6000): array
    {
        return ['line_type' => 'stock', 'product_id' => $erp['product']->id, 'quantity' => $quantity, 'unit_price' => $price, 'vat_rate' => 18];
    }

    private function receive(array $erp, array $order, float $quantity, int $line = 0): TestResponse
    {
        return $this->as($erp, 'storekeeper')->postJson("/api/erp/procurement/orders/{$order['id']}/receive", [
            'delivery_note' => 'DN-1001',
            'warehouse_id' => $erp['main']->id,
            'lines' => [['purchase_order_line_id' => $order['lines'][$line]['id'], 'quantity' => $quantity]],
        ]);
    }

    private function invoice(array $erp, array $order, float $quantity, float $price, string $number = 'INV-7781', int $line = 0): TestResponse
    {
        return $this->as($erp, 'accountant')->postJson('/api/erp/procurement/invoices', [
            'purchase_order_id' => $order['id'],
            'supplier_invoice_number' => $number,
            'invoice_date' => now()->toDateString(),
            'lines' => [['purchase_order_line_id' => $order['lines'][$line]['id'], 'quantity' => $quantity, 'unit_price' => $price]],
        ]);
    }

    private function onHand(array $erp): float
    {
        return (float) StockBalance::acrossTenants()->where('product_id', $erp['product']->id)->where('warehouse_id', $erp['main']->id)->sum('quantity');
    }

    /** @return array<string, float> account system key => net debit */
    private function journalFor(string $type, int $id): array
    {
        $entry = JournalEntry::acrossTenants()->where('source_type', $type)->where('source_id', $id)->where('purpose', 'post')->firstOrFail();
        $lines = JournalLine::query()->where('journal_entry_id', $entry->id)->get();
        $accounts = Account::acrossTenants()->whereIn('id', $lines->pluck('account_id'))->get()->keyBy('id');

        $this->assertSame(
            (int) round($lines->sum('debit') * 100), (int) round($lines->sum('credit') * 100),
            "Journal {$entry->number} must balance.",
        );

        $net = [];
        foreach ($lines as $line) {
            $key = $accounts[$line->account_id]->system_key ?? $accounts[$line->account_id]->code;
            $net[$key] = round(($net[$key] ?? 0) + (float) $line->debit - (float) $line->credit, 2);
        }

        return $net;
    }

    public function test_requisitions_need_one_approval_below_the_threshold_and_a_senior_second_above_it(): void
    {
        $erp = $this->erp();

        $small = $this->requisition($erp, 10, 6000)->assertCreated()->assertJsonPath('data.status', 'draft')->json('data.id');
        $this->postJson("/api/erp/procurement/requisitions/{$small}/submit")->assertOk()->assertJsonPath('data.approvals_required', 1);
        $this->as($erp, 'hod')->postJson("/api/erp/procurement/requisitions/{$small}/approve", ['comment' => 'Needed'])
            ->assertOk()->assertJsonPath('data.status', 'approved')
            ->assertJsonPath('data.approvals.0.user.id', $erp['hod']->id)
            ->assertJsonPath('data.approvals.0.comment', 'Needed');

        $large = $this->requisition($erp, 1000, 6000)->assertCreated()->json('data.id');
        $this->as($erp, 'officer')->postJson("/api/erp/procurement/requisitions/{$large}/submit")->assertOk()->assertJsonPath('data.approvals_required', 2);

        $this->as($erp, 'hod')->postJson("/api/erp/procurement/requisitions/{$large}/approve")->assertOk()->assertJsonPath('data.status', 'submitted');
        $this->as($erp, 'hod')->postJson("/api/erp/procurement/requisitions/{$large}/approve")
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'already approved'));
        $this->as($erp, 'manager')->postJson("/api/erp/procurement/requisitions/{$large}/approve")
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'senior approver'));
        $this->as($erp, 'finance')->postJson("/api/erp/procurement/requisitions/{$large}/approve")->assertOk()->assertJsonPath('data.status', 'approved');

        $this->assertSame([1, 2], ProcurementApproval::acrossTenants()->where('approvable_type', 'PurchaseRequisition')
            ->where('approvable_id', $large)->orderBy('id')->pluck('level')->all());

        // Nobody approves their own requisition.
        $own = $this->requisition($erp, 1, 6000, 'hod')->assertCreated()->json('data.id');
        $this->as($erp, 'hod')->postJson("/api/erp/procurement/requisitions/{$own}/submit")->assertOk();
        $this->as($erp, 'hod')->postJson("/api/erp/procurement/requisitions/{$own}/approve")
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'someone else'));

        // A rejection needs a reason and is final.
        $this->as($erp, 'manager')->postJson("/api/erp/procurement/requisitions/{$own}/reject")->assertStatus(422);
        $this->as($erp, 'manager')->postJson("/api/erp/procurement/requisitions/{$own}/reject", ['comment' => 'Not budgeted'])
            ->assertOk()->assertJsonPath('data.status', 'rejected');
    }

    public function test_quotations_are_compared_with_the_lowest_marked_and_the_winner_becomes_an_order(): void
    {
        $erp = $this->erp();
        [$a, $b, $c] = app(TenantContext::class)->forCompany($erp['company'], fn () => [
            $erp['supplier'],
            Supplier::create(['code' => 'SUP-2', 'name' => 'Pwani Plastics']),
            Supplier::create(['code' => 'SUP-3', 'name' => 'Arusha Packaging']),
        ]);

        $req = $this->requisition($erp, 100, 6000)->json('data.id');
        $this->postJson("/api/erp/procurement/requisitions/{$req}/submit")->assertOk();
        $this->as($erp, 'hod')->postJson("/api/erp/procurement/requisitions/{$req}/approve")->assertOk();

        $rfq = $this->as($erp, 'officer')->postJson('/api/erp/procurement/rfqs', [
            'purchase_requisition_id' => $req, 'title' => 'Water cartons', 'supplier_ids' => [$a->id, $b->id, $c->id],
        ])->assertCreated()->json('data');
        $this->postJson("/api/erp/procurement/rfqs/{$rfq['id']}/send")->assertOk()->assertJsonPath('data.status', 'sent');

        $line = $rfq['lines'][0]['id'];
        foreach ([[$a, 6100, 7], [$b, 5900, 14], [$c, 6050, 3]] as [$supplier, $price, $lead]) {
            $this->postJson("/api/erp/procurement/rfqs/{$rfq['id']}/quotations", [
                'supplier_id' => $supplier->id, 'lead_time_days' => $lead,
                'lines' => [['purchase_rfq_line_id' => $line, 'unit_price' => $price, 'vat_rate' => 18]],
            ])->assertCreated();
        }

        $comparison = $this->getJson("/api/erp/procurement/rfqs/{$rfq['id']}/comparison")->assertOk()->json('data');
        $this->assertSame('Pwani Plastics', $comparison['quotations'][0]['supplier']['name']);
        $this->assertTrue($comparison['quotations'][0]['lowest']);
        $this->assertFalse($comparison['quotations'][1]['lowest']);
        $lowest = collect($comparison['lines'][0]['prices'])->firstWhere('lowest', true);
        $this->assertEquals(5900, $lowest['unit_price']);

        $fastest = collect($comparison['quotations'])->firstWhere('supplier.id', $c->id)['id'];
        $this->postJson("/api/erp/procurement/rfqs/{$rfq['id']}/award", ['quotation_id' => $fastest])->assertStatus(422);
        $this->postJson("/api/erp/procurement/rfqs/{$rfq['id']}/award", [
            'quotation_id' => $fastest, 'reason' => 'Fastest delivery for the Arusha depot',
        ])->assertOk()->assertJsonPath('data.status', 'awarded')->assertJsonPath('data.selection_reason', 'Fastest delivery for the Arusha depot');

        $order = $this->postJson('/api/erp/procurement/orders', ['supplier_quotation_id' => $fastest])
            ->assertCreated()->assertJsonPath('data.supplier_id', $c->id)->assertJsonPath('data.purchase_requisition_id', $req)->json('data');
        $this->assertEquals(6050, $order['lines'][0]['unit_price']);
        $this->assertEquals(605000 * 1.18, (float) $order['total']);
        $this->getJson("/api/erp/procurement/requisitions/{$req}")->assertJsonPath('data.status', 'ordered');

        // One order per selected quotation.
        $this->postJson('/api/erp/procurement/orders', ['supplier_quotation_id' => $fastest])->assertStatus(422);
    }

    public function test_goods_are_received_through_a_posted_grn_and_never_beyond_what_was_ordered(): void
    {
        $erp = $this->erp();
        $order = $this->sentOrder($erp, [$this->stockLine($erp, 100)]);

        $grn = $this->receive($erp, $order, 60)->assertCreated()->json('data');
        $this->assertSame(60.0, $this->onHand($erp));
        $document = StockDocument::acrossTenants()->findOrFail($grn['stock_document_id']);
        $this->assertSame('posted', $document->status);
        $this->assertSame('purchase_order', $document->source_type);
        $this->assertSame($order['id'], (int) $document->source_id);
        $this->assertSame($erp['supplier']->id, $document->supplier_id);
        $this->assertSame(['inventory' => 360000.0, 'grni' => -360000.0], $this->journalFor('StockDocument', $document->id));

        $this->getJson("/api/erp/procurement/orders/{$order['id']}")
            ->assertJsonPath('data.status', 'partially_received')->assertJsonPath('data.lines.0.received_quantity', '60.000');

        $this->receive($erp, $order, 41)->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'Cannot receive more than was ordered'));
        $this->assertSame(60.0, $this->onHand($erp), 'A refused receipt must leave no trace.');
        $this->assertSame(1, StockDocument::acrossTenants()->where('source_type', 'purchase_order')->count());

        $this->receive($erp, $order, 40)->assertCreated();
        $this->getJson("/api/erp/procurement/orders/{$order['id']}")->assertJsonPath('data.status', 'received');
        $this->receive($erp, $order, 1)->assertStatus(422);
        $this->assertSame(100.0, $this->onHand($erp));

        // A tolerance lets a little more in, and no further.
        app(TenantContext::class)->forCompany($erp['company'], fn () => ProcurementSetting::current()->update(['receipt_tolerance_percent' => 5]));
        $second = $this->sentOrder($erp, [$this->stockLine($erp, 100)]);
        $this->receive($erp, $second, 106)->assertStatus(422);
        $this->receive($erp, $second, 105)->assertCreated();
    }

    public function test_the_three_way_match_flags_a_price_variance_that_needs_approval_before_posting(): void
    {
        $erp = $this->erp();
        $order = $this->sentOrder($erp, [$this->stockLine($erp, 100)]);
        $this->receive($erp, $order, 100)->assertCreated();

        $invoice = $this->invoice($erp, $order, 100, 6500)->assertCreated()
            ->assertJsonPath('data.status', 'awaiting_approval')
            ->assertJsonPath('data.match_status', 'variance')
            ->assertJsonPath('data.lines.0.flagged', true)
            ->assertJsonPath('data.lines.0.price_variance', '50000.00')
            ->json('data');

        $this->as($erp, 'accountant')->postJson("/api/erp/procurement/invoices/{$invoice['id']}/post")
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'needs approval'));
        $this->as($erp, 'accountant')->postJson("/api/erp/procurement/invoices/{$invoice['id']}/approve")->assertForbidden();
        $this->as($erp, 'finance')->postJson("/api/erp/procurement/invoices/{$invoice['id']}/approve", ['comment' => 'Fuel surcharge agreed'])
            ->assertOk()->assertJsonPath('data.status', 'approved');

        $this->as($erp, 'accountant')->postJson("/api/erp/procurement/invoices/{$invoice['id']}/post")->assertOk()->assertJsonPath('data.status', 'posted');

        // 100 received at 6,000 clears GRNI; the 500 a unit more is price variance; VAT on 650,000.
        $this->assertSame([
            'grni' => 600000.0, 'purchase_price_variance' => 50000.0, 'vat_input' => 117000.0, 'payable' => -767000.0,
        ], $this->journalFor('SupplierInvoice', $invoice['id']));

        // Within tolerance there is nothing to approve.
        $matched = $this->sentOrder($erp, [$this->stockLine($erp, 10)]);
        $this->receive($erp, $matched, 10)->assertCreated();
        $this->invoice($erp, $matched, 10, 6100, 'INV-7790')->assertCreated()->assertJsonPath('data.status', 'draft')->assertJsonPath('data.match_status', 'matched');

        // Invoicing more than was received is a quantity variance.
        $short = $this->sentOrder($erp, [$this->stockLine($erp, 10)]);
        $this->receive($erp, $short, 6)->assertCreated();
        $this->invoice($erp, $short, 10, 6000, 'INV-7791')->assertCreated()
            ->assertJsonPath('data.status', 'awaiting_approval')->assertJsonPath('data.lines.0.quantity_variance', '4.000');
    }

    /** Acceptance criterion 9. */
    public function test_a_purchase_invoice_and_its_payment_post_once_and_never_twice(): void
    {
        $erp = $this->erp();
        $order = $this->sentOrder($erp, [$this->stockLine($erp, 50)]);
        $this->receive($erp, $order, 50)->assertCreated();

        $invoice = $this->invoice($erp, $order, 50, 6000)->assertCreated()->assertJsonPath('data.status', 'draft')->json('data');
        $this->invoice($erp, $order, 50, 6000)->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'already been entered'));

        $this->as($erp, 'accountant')->postJson("/api/erp/procurement/invoices/{$invoice['id']}/post")->assertOk();
        $this->as($erp, 'accountant')->postJson("/api/erp/procurement/invoices/{$invoice['id']}/post")
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'already been posted'));

        $this->assertSame(1, JournalEntry::acrossTenants()->where('source_type', 'SupplierInvoice')->where('source_id', $invoice['id'])->count());
        $this->assertSame(['grni' => 300000.0, 'vat_input' => 54000.0, 'payable' => -354000.0], $this->journalFor('SupplierInvoice', $invoice['id']));
        $this->getJson("/api/erp/procurement/orders/{$order['id']}")->assertJsonPath('data.status', 'closed')->assertJsonPath('data.lines.0.invoiced_quantity', '50.000');

        $bank = app(TenantContext::class)->forCompany($erp['company'], fn () => Account::where('system_key', 'bank')->value('id'));
        $inventory = app(TenantContext::class)->forCompany($erp['company'], fn () => Account::where('system_key', 'inventory')->value('id'));

        $pay = fn (float $amount, int $account) => $this->as($erp, 'cashier')->postJson('/api/erp/procurement/payments', [
            'supplier_id' => $erp['supplier']->id, 'account_id' => $account, 'amount' => $amount, 'reference' => 'TRX-55',
            'allocations' => [['supplier_invoice_id' => $invoice['id'], 'amount' => $amount]],
        ]);

        $pay(354000, $inventory)->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'cash or bank'));
        $pay(400000, $bank)->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'outstanding'));

        $payment = $pay(354000, $bank)->assertCreated()->assertJsonPath('data.status', 'draft')->json('data');
        $this->as($erp, 'cashier')->postJson("/api/erp/procurement/payments/{$payment['id']}/post")->assertOk()->assertJsonPath('data.status', 'posted');
        $this->as($erp, 'cashier')->postJson("/api/erp/procurement/payments/{$payment['id']}/post")->assertStatus(422);

        $this->assertSame(1, JournalEntry::acrossTenants()->where('source_type', 'SupplierPayment')->where('source_id', $payment['id'])->count());
        $this->assertSame(['payable' => 354000.0, 'bank' => -354000.0], $this->journalFor('SupplierPayment', $payment['id']));
        $this->getJson("/api/erp/procurement/invoices/{$invoice['id']}")->assertJsonPath('data.payment_status', 'paid')->assertJsonPath('data.outstanding', 0);

        // The invoice is settled: a second payment against it is refused.
        $pay(1000, $bank)->assertStatus(422);

        // Payables and GRNI are both back to nothing, and every journal balances.
        $balances = app(TenantContext::class)->forCompany($erp['company'], function () {
            $net = fn (string $key) => round((float) JournalLine::query()->whereIn('account_id', Account::where('system_key', $key)->pluck('id'))->selectRaw('COALESCE(SUM(debit - credit), 0) as v')->value('v'), 2);

            return ['payable' => $net('payable'), 'grni' => $net('grni')];
        });
        $this->assertEquals(['payable' => 0.0, 'grni' => 0.0], $balances);
        $this->assertEquals(JournalLine::query()->sum('debit'), JournalLine::query()->sum('credit'));
    }

    public function test_service_lines_are_confirmed_not_received_and_post_to_their_expense_account(): void
    {
        $erp = $this->erp();
        $repairs = app(TenantContext::class)->forCompany($erp['company'], fn () => Account::where('system_key', 'vehicle_maintenance')->value('id'));

        $order = $this->sentOrder($erp, [
            ['line_type' => 'service', 'description' => 'Forklift gearbox repair', 'quantity' => 1, 'unit_price' => 850000, 'vat_rate' => 18, 'expense_account_id' => $repairs],
        ]);

        $this->receive($erp, $order, 1)->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'is a service'));

        $this->as($erp, 'storekeeper')->postJson("/api/erp/procurement/orders/{$order['id']}/confirm-service", [
            'lines' => [['purchase_order_line_id' => $order['lines'][0]['id'], 'quantity' => 1]],
        ])->assertCreated()->assertJsonPath('data.kind', 'service')->assertJsonPath('data.stock_document_id', null);
        $this->getJson("/api/erp/procurement/orders/{$order['id']}")->assertJsonPath('data.status', 'received');

        $invoice = $this->invoice($erp, $order, 1, 850000, 'GAR-0091')->assertCreated()->assertJsonPath('data.status', 'draft')->json('data');
        $this->as($erp, 'accountant')->postJson("/api/erp/procurement/invoices/{$invoice['id']}/post")->assertOk();

        $this->assertSame(['vehicle_maintenance' => 850000.0, 'vat_input' => 153000.0, 'payable' => -1003000.0], $this->journalFor('SupplierInvoice', $invoice['id']));
    }

    public function test_purchase_orders_above_the_threshold_need_a_senior_second_approval(): void
    {
        $erp = $this->erp();
        $order = $this->as($erp, 'officer')->postJson('/api/erp/procurement/orders', [
            'supplier_id' => $erp['supplier']->id, 'lines' => [$this->stockLine($erp, 1000)],
        ])->assertCreated()->json('data');

        $this->as($erp, 'accountant')->postJson("/api/erp/procurement/orders/{$order['id']}/receive", ['lines' => [['purchase_order_line_id' => $order['lines'][0]['id'], 'quantity' => 1]]])
            ->assertForbidden();
        $this->as($erp, 'officer')->postJson("/api/erp/procurement/orders/{$order['id']}/receive", ['lines' => [['purchase_order_line_id' => $order['lines'][0]['id'], 'quantity' => 1]]])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'is draft'));
        $this->as($erp, 'officer')->postJson("/api/erp/procurement/orders/{$order['id']}/submit")->assertOk()->assertJsonPath('data.approvals_required', 2);
        $this->as($erp, 'manager')->postJson("/api/erp/procurement/orders/{$order['id']}/approve")->assertOk()->assertJsonPath('data.status', 'submitted');
        $this->as($erp, 'hod')->postJson("/api/erp/procurement/orders/{$order['id']}/approve")->assertStatus(422);
        $this->as($erp, 'ceo')->postJson("/api/erp/procurement/orders/{$order['id']}/approve")->assertOk()->assertJsonPath('data.status', 'approved');

        $this->receive($erp, $order, 1)->assertCreated();
        $this->as($erp, 'officer')->postJson("/api/erp/procurement/orders/{$order['id']}/cancel", ['reason' => 'No longer needed'])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'close it instead'));
        $this->as($erp, 'officer')->postJson("/api/erp/procurement/orders/{$order['id']}/close")->assertOk()->assertJsonPath('data.status', 'closed');
    }

    public function test_people_without_the_permission_are_refused(): void
    {
        $erp = $this->erp();
        $order = $this->sentOrder($erp, [$this->stockLine($erp, 10)]);
        $this->receive($erp, $order, 10)->assertCreated();
        $invoice = $this->invoice($erp, $order, 10, 6000)->json('data');

        $this->as($erp, 'employee')->getJson('/api/erp/procurement/overview')->assertForbidden();
        $this->as($erp, 'employee')->getJson('/api/erp/procurement/orders')->assertForbidden();
        $this->as($erp, 'storekeeper')->postJson('/api/erp/procurement/orders', ['supplier_id' => $erp['supplier']->id, 'lines' => [$this->stockLine($erp, 1)]])->assertForbidden();
        $this->as($erp, 'officer')->postJson("/api/erp/procurement/invoices/{$invoice['id']}/post")->assertForbidden();
        $this->as($erp, 'cashier')->postJson("/api/erp/procurement/invoices/{$invoice['id']}/post")->assertForbidden();
        $this->as($erp, 'accountant')->postJson('/api/erp/procurement/payments', [])->assertForbidden();
        $req = $this->requisition($erp, 1, 6000)->json('data.id');
        $this->as($erp, 'officer')->postJson("/api/erp/procurement/requisitions/{$req}/submit")->assertOk();
        $this->as($erp, 'officer')->postJson("/api/erp/procurement/requisitions/{$req}/approve")->assertForbidden();
        $this->as($erp, 'storekeeper')->postJson("/api/erp/procurement/requisitions/{$req}/approve")->assertForbidden();
        $this->as($erp, 'officer')->putJson('/api/erp/procurement/settings', [])->assertForbidden();

        $this->assertSame('draft', $this->as($erp, 'officer')->getJson("/api/erp/procurement/invoices/{$invoice['id']}")->json('data.status'));
    }

    public function test_another_companys_procurement_records_are_invisible_and_unusable(): void
    {
        $ours = $this->erp('Maji Bora');
        $theirs = $this->erp('Kilimanjaro Springs');

        $order = $this->sentOrder($theirs, [$this->stockLine($theirs, 10)]);
        $req = $this->requisition($theirs, 1, 6000)->json('data.id');

        $this->as($ours, 'officer')->getJson("/api/erp/procurement/orders/{$order['id']}")->assertNotFound();
        $this->as($ours, 'officer')->getJson("/api/erp/procurement/requisitions/{$req}")->assertNotFound();
        $this->as($ours, 'storekeeper')->postJson("/api/erp/procurement/orders/{$order['id']}/receive", [
            'lines' => [['purchase_order_line_id' => $order['lines'][0]['id'], 'quantity' => 1]],
        ])->assertNotFound();
        $this->as($ours, 'accountant')->postJson('/api/erp/procurement/invoices', [
            'purchase_order_id' => $order['id'], 'supplier_invoice_number' => 'X-1',
            'lines' => [['purchase_order_line_id' => $order['lines'][0]['id'], 'quantity' => 1, 'unit_price' => 1]],
        ])->assertUnprocessable()->assertJsonValidationErrors('purchase_order_id');
        $this->as($ours, 'officer')->getJson("/api/erp/procurement/statement/{$theirs['supplier']->id}")->assertNotFound();
        $this->as($ours, 'officer')->getJson('/api/erp/procurement/orders')->assertOk()->assertJsonPath('total', 0);

        // Their supplier cannot be put on our order either.
        $this->as($ours, 'officer')->postJson('/api/erp/procurement/orders', [
            'supplier_id' => $theirs['supplier']->id, 'lines' => [$this->stockLine($ours, 1)],
        ])->assertUnprocessable()->assertJsonValidationErrors('supplier_id');
    }

    public function test_ageing_and_the_supplier_statement_follow_posted_invoices_and_payments(): void
    {
        $erp = $this->erp();
        $order = $this->sentOrder($erp, [$this->stockLine($erp, 20)]);
        $this->receive($erp, $order, 20)->assertCreated();

        $invoice = $this->as($erp, 'accountant')->postJson('/api/erp/procurement/invoices', [
            'purchase_order_id' => $order['id'], 'supplier_invoice_number' => 'OLD-1',
            'invoice_date' => now()->subDays(50)->toDateString(), 'due_date' => now()->subDays(40)->toDateString(),
            'lines' => [['purchase_order_line_id' => $order['lines'][0]['id'], 'quantity' => 20, 'unit_price' => 6000]],
        ])->assertCreated()->json('data');
        $this->as($erp, 'accountant')->postJson("/api/erp/procurement/invoices/{$invoice['id']}/post")->assertOk();

        $bank = app(TenantContext::class)->forCompany($erp['company'], fn () => Account::where('system_key', 'bank')->value('id'));
        $this->as($erp, 'cashier')->postJson('/api/erp/procurement/payments', [
            'supplier_id' => $erp['supplier']->id, 'account_id' => $bank, 'amount' => 41600, 'post' => true,
            'allocations' => [['supplier_invoice_id' => $invoice['id'], 'amount' => 41600]],
        ])->assertCreated()->assertJsonPath('data.status', 'posted');

        $ageing = $this->as($erp, 'officer')->getJson('/api/erp/procurement/ageing')->assertOk()->json('data');
        $this->assertEquals(100000, $ageing['totals']['days_31_60']);
        $this->assertEquals(100000, $ageing['totals']['total']);
        $this->assertSame($erp['supplier']->id, $ageing['rows'][0]['supplier']['id']);

        $statement = $this->getJson("/api/erp/procurement/statement/{$erp['supplier']->id}")->assertOk()->json('data');
        $this->assertCount(2, $statement['entries']);
        $this->assertEquals(141600, $statement['total_invoiced']);
        $this->assertEquals(100000, $statement['closing_balance']);

        $this->getJson('/api/erp/procurement/overview')->assertOk()
            ->assertJsonPath('data.payables_outstanding', 100000)->assertJsonPath('data.payables_overdue', 100000);
    }
}
