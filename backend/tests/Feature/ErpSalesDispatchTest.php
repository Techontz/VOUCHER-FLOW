<?php

namespace Tests\Feature;

use App\Models\Erp\Customer;
use App\Models\Erp\Product;
use App\Models\Erp\Sales\LoadingOrder;
use App\Models\Erp\StockBalance;
use App\Models\Erp\StockDocument;
use App\Models\Erp\StockMovement;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Sales orders through finance verification and dispatch to proof of
 * delivery. Acceptance criteria 3, 4, 5 and 6 of the requirements live here,
 * with the invoice, receipt and credit note postings they rely on.
 */
class ErpSalesDispatchTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    /** A wholesale tenant with sales people, dispatch, stock and two customers. */
    private function erp(string $name = 'Maji Bora', array $settings = []): array
    {
        $erp = $this->setUpErp($this->makeTenant($name), 'wholesale', $settings);

        return app(TenantContext::class)->forCompany($erp['company'], function () use ($erp) {
            $company = $erp['company'];
            $slug = $company->slug;
            $make = fn (string $key, string $role) => User::create([
                'company_id' => $company->id, 'name' => ucfirst($key)." {$slug}",
                'email' => "{$key}@{$slug}.test", 'password' => 'Password123!', 'role' => $role, 'status' => 'active',
            ]);

            return [
                ...$erp,
                'sales' => $make('sales', User::ROLE_SALES),
                'dispatch' => $make('dispatch', User::ROLE_DISPATCH),
                'prepay' => Customer::create(['company_id' => $company->id, 'code' => 'C-PRE', 'name' => 'Mama Ntilie Kiosk', 'requires_prepayment' => true]),
                'credit' => Customer::create([
                    'company_id' => $company->id, 'code' => 'C-CRD', 'name' => 'Kariakoo Wholesalers',
                    'requires_prepayment' => false, 'credit_limit' => 2000000, 'payment_terms_days' => 30,
                ]),
            ];
        });
    }

    private function as(array $erp, string $who): self
    {
        return $this->actingAs($erp[$who], 'sanctum');
    }

    private function stock(array $erp, float $quantity, string $warehouse = 'main', float $cost = 6000): void
    {
        $id = $this->as($erp, 'storekeeper')->postJson('/api/erp/stock-documents', [
            'type' => 'grn', 'warehouse_id' => $erp[$warehouse]->id,
            'lines' => [['product_id' => $erp['product']->id, 'quantity' => $quantity, 'unit_cost' => $cost]],
        ])->assertCreated()->json('data.id');
        $this->as($erp, 'warehouse_manager')->postJson("/api/erp/stock-documents/{$id}/post")->assertOk();
    }

    private function onHand(array $erp, string $warehouse = 'main'): float
    {
        return (float) StockBalance::acrossTenants()->where('product_id', $erp['product']->id)->where('warehouse_id', $erp[$warehouse]->id)->sum('quantity');
    }

    /** A submitted order for `quantity` cartons at 10,000 each, 18% VAT. */
    private function order(array $erp, string $customer, float $quantity = 10, float $price = 10000): int
    {
        $id = $this->as($erp, 'sales')->postJson('/api/erp/sales/orders', [
            'customer_id' => $erp[$customer]->id,
            'lines' => [['product_id' => $erp['product']->id, 'quantity' => $quantity, 'unit_price' => $price]],
        ])->assertCreated()->json('data.id');
        $this->as($erp, 'sales')->postJson("/api/erp/sales/orders/{$id}/submit")->assertOk();

        return $id;
    }

    private function approve(array $erp, int $order, array $body = []): TestResponse
    {
        return $this->as($erp, 'finance')->postJson("/api/erp/sales/orders/{$order}/approve", $body);
    }

    private function invoice(array $erp, int $order, ?int $loading = null): int
    {
        $id = $this->as($erp, 'accountant')->postJson("/api/erp/sales/orders/{$order}/invoice", array_filter(['loading_order_id' => $loading]))
            ->assertCreated()->json('data.id');
        $this->as($erp, 'accountant')->postJson("/api/erp/sales/invoices/{$id}/post")->assertOk();

        return $id;
    }

    private function receipt(array $erp, int $invoice, float $amount, string $who = 'cashier'): int
    {
        $bank = DB::table('accounts')->where('company_id', $erp['company']->id)->where('system_key', 'bank')->value('id');

        return $this->as($erp, $who)->postJson('/api/erp/sales/receipts', [
            'customer_id' => DB::table('sales_invoices')->where('id', $invoice)->value('customer_id'),
            'account_id' => $bank, 'method' => 'bank_transfer', 'reference' => 'CRDB-'.$invoice,
            'allocations' => [['sales_invoice_id' => $invoice, 'amount' => $amount]],
        ])->assertCreated()->json('data.id');
    }

    private function loading(array $erp, int $order, string $warehouse = 'main', array $quantities = []): TestResponse
    {
        return $this->as($erp, 'dispatch')->postJson('/api/erp/dispatch/loading-orders', array_filter([
            'sales_order_id' => $order, 'warehouse_id' => $erp[$warehouse]->id,
            'vehicle_number' => 'T 123 ABC', 'driver_name' => 'Juma Mussa', 'quantities' => $quantities,
        ]));
    }

    /** Debits and credits by system key for one source document. */
    private function journal(string $type, int $id, string $purpose = 'post'): array
    {
        $rows = DB::table('journal_lines as l')
            ->join('journal_entries as e', 'e.id', '=', 'l.journal_entry_id')
            ->join('accounts as a', 'a.id', '=', 'l.account_id')
            ->where('e.source_type', $type)->where('e.source_id', $id)->where('e.purpose', $purpose)
            ->selectRaw('a.system_key as k, SUM(l.debit) as d, SUM(l.credit) as c')->groupBy('a.system_key')->get();

        return $rows->mapWithKeys(fn ($r) => [$r->k => [round((float) $r->d, 2), round((float) $r->c, 2)]])->sortKeys()->all();
    }

    /** Takes a ready order all the way out of the gate, loading `loaded` of it. */
    private function dispatchOut(array $erp, int $order, ?float $loaded = null): array
    {
        $loading = $this->loading($erp, $order)->assertCreated()->json('data');
        $line = $loading['lines'][0]['id'];
        $base = "/api/erp/dispatch/loading-orders/{$loading['id']}";

        $this->as($erp, 'storekeeper')->putJson("{$base}/loaded", ['quantities' => [$line => $loaded ?? (float) $loading['lines'][0]['quantity_approved']]])->assertOk();
        $this->as($erp, 'storekeeper')->postJson("{$base}/confirm-loading")->assertOk();
        $this->as($erp, 'dispatch')->postJson("{$base}/confirm-driver", ['name' => 'Juma Mussa'])->assertOk();
        $this->as($erp, 'dispatch')->postJson("{$base}/confirm-security", ['name' => 'Saidi Hamisi'])->assertOk();
        $this->as($erp, 'dispatch')->postJson("{$base}/delivery-note")->assertOk();
        $this->as($erp, 'dispatch')->postJson("{$base}/gate-pass")->assertOk();

        return ['id' => $loading['id'], 'line' => $line, 'base' => $base];
    }

    public function test_a_prepayment_order_waits_for_verified_payment_before_a_loading_order(): void
    {
        $erp = $this->erp();
        $this->stock($erp, 50);
        $order = $this->order($erp, 'prepay');

        $this->approve($erp, $order)->assertOk()->assertJsonPath('data.status', 'awaiting_payment')->assertJsonPath('data.payment_mode', 'prepayment');
        $this->loading($erp, $order)->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'waiting for payment verification'));

        $invoice = $this->invoice($erp, $order);
        $receipt = $this->receipt($erp, $invoice, 118000, 'accountant');

        // Recorded is not verified: the truck still may not be loaded.
        $this->loading($erp, $order)->assertStatus(422);
        $this->as($erp, 'cashier')->postJson("/api/erp/sales/receipts/{$receipt}/verify")->assertForbidden();
        $this->as($erp, 'accountant')->postJson("/api/erp/sales/receipts/{$receipt}/verify")
            ->assertStatus(422)->assertJsonPath('message', 'You recorded this payment, so someone else in finance must verify it.');
        $this->assertSame('awaiting_payment', DB::table('sales_orders')->where('id', $order)->value('status'));

        $this->as($erp, 'finance')->postJson("/api/erp/sales/receipts/{$receipt}/verify")->assertOk()->assertJsonPath('data.status', 'verified');
        $this->assertSame('ready', DB::table('sales_orders')->where('id', $order)->value('status'));

        $this->loading($erp, $order)->assertCreated()->assertJsonPath('data.status', 'open');
        $this->assertSame('loading', DB::table('sales_orders')->where('id', $order)->value('status'));
    }

    public function test_a_part_payment_does_not_release_a_prepayment_order(): void
    {
        $erp = $this->erp();
        $this->stock($erp, 50);
        $order = $this->order($erp, 'prepay');
        $this->approve($erp, $order)->assertOk();
        $invoice = $this->invoice($erp, $order);

        $receipt = $this->receipt($erp, $invoice, 50000);
        $this->as($erp, 'finance')->postJson("/api/erp/sales/receipts/{$receipt}/verify")->assertOk();

        $this->assertSame('awaiting_payment', DB::table('sales_orders')->where('id', $order)->value('status'));
        $this->loading($erp, $order)->assertStatus(422);
    }

    public function test_a_credit_customer_proceeds_only_within_the_credit_policy(): void
    {
        $erp = $this->erp();

        // 10 × 10,000 + 18% = 118,000, well within 2,000,000.
        $within = $this->order($erp, 'credit');
        $this->approve($erp, $within)->assertOk()->assertJsonPath('data.status', 'ready')->assertJsonPath('data.payment_mode', 'credit')
            ->assertJsonPath('data.policy_check.passed', true);

        // 160 × 10,000 + 18% = 1,888,000 more: over the limit with the first order still open.
        $over = $this->order($erp, 'credit', 160);
        $this->approve($erp, $over)->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'credit limit') && str_contains($m, 'override'));
        $this->assertSame('submitted', DB::table('sales_orders')->where('id', $over)->value('status'));

        // A salesperson cannot override; finance can, with a reason that stays on the record.
        $this->as($erp, 'sales')->postJson("/api/erp/sales/orders/{$over}/approve", ['override_reason' => 'Director agreed'])->assertForbidden();
        $this->approve($erp, $over, ['override_reason' => 'Bank guarantee received from CRDB, reference BG-2026-114'])
            ->assertOk()->assertJsonPath('data.status', 'ready')
            ->assertJsonPath('data.override_reason', 'Bank guarantee received from CRDB, reference BG-2026-114')
            ->assertJsonPath('data.overridden_by', $erp['finance']->id)
            ->assertJsonPath('data.policy_check.passed', false);
        $this->assertDatabaseHas('audit_logs', ['action' => 'sales.order.credit_override', 'entity_id' => $over]);
    }

    public function test_a_credit_customer_with_an_overdue_invoice_is_refused(): void
    {
        $erp = $this->erp();
        $first = $this->order($erp, 'credit');
        $this->approve($erp, $first)->assertOk();
        $invoice = $this->invoice($erp, $first);
        DB::table('sales_invoices')->where('id', $invoice)->update(['invoice_date' => now()->subDays(45), 'due_date' => now()->subDays(15)]);

        $second = $this->order($erp, 'credit', 1);
        $this->approve($erp, $second)->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'past the 30-day payment terms') && str_contains($m, '15 days overdue'));

        // Once paid, the same order goes through.
        $receipt = $this->receipt($erp, $invoice, 118000);
        $this->as($erp, 'finance')->postJson("/api/erp/sales/receipts/{$receipt}/verify")->assertOk();
        $this->approve($erp, $second)->assertOk()->assertJsonPath('data.status', 'ready');
    }

    public function test_a_sales_order_cannot_be_loaded_without_stock(): void
    {
        $erp = $this->erp();
        $order = $this->order($erp, 'credit');
        $this->approve($erp, $order)->assertOk();

        $this->loading($erp, $order)->assertStatus(422)
            ->assertJsonPath('message', 'Not enough Water 500ml x24 in Main store: 0 available, 10 needed. The order cannot be loaded from there.');

        // Stock in another place does not help this one.
        $this->stock($erp, 30, 'depot');
        $this->loading($erp, $order)->assertStatus(422);

        // Enough at creation, but gone by the time the truck is loaded: the ledger refuses and nothing moves.
        $this->stock($erp, 10);
        $loading = $this->loading($erp, $order)->assertCreated()->json('data');
        $issue = $this->as($erp, 'storekeeper')->postJson('/api/erp/stock-documents', [
            'type' => 'issue', 'warehouse_id' => $erp['main']->id, 'lines' => [['product_id' => $erp['product']->id, 'quantity' => 5]],
        ])->json('data.id');
        $this->as($erp, 'warehouse_manager')->postJson("/api/erp/stock-documents/{$issue}/post")->assertOk();

        $base = "/api/erp/dispatch/loading-orders/{$loading['id']}";
        $this->as($erp, 'storekeeper')->putJson("{$base}/loaded", ['quantities' => [$loading['lines'][0]['id'] => 10]])->assertOk();
        $this->as($erp, 'storekeeper')->postJson("{$base}/confirm-loading")->assertStatus(422)
            ->assertJsonPath('message', 'Not enough Water 500ml x24 in Main store: 5 on hand, 10 needed.');

        $this->assertSame(5.0, $this->onHand($erp));
        $this->assertSame('open', LoadingOrder::acrossTenants()->find($loading['id'])->status);
        $this->assertSame(0, StockDocument::acrossTenants()->where('source_type', 'loading_order')->count());
    }

    public function test_open_loading_orders_hold_stock_against_each_other(): void
    {
        $erp = $this->erp();
        $this->stock($erp, 15);
        $a = $this->order($erp, 'credit');
        $b = $this->order($erp, 'credit');
        $this->approve($erp, $a)->assertOk();
        $this->approve($erp, $b)->assertOk();

        $this->loading($erp, $a)->assertCreated();
        $this->loading($erp, $b)->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, '5 available (15 on hand, 10 held for other loading orders)'));
    }

    public function test_loading_order_loaded_quantities_and_delivery_note_agree_and_stock_moves_once(): void
    {
        $erp = $this->erp();
        $this->stock($erp, 40);
        $order = $this->order($erp, 'credit', 12);
        $orderLine = DB::table('sales_order_lines')->where('sales_order_id', $order)->value('id');
        $this->approve($erp, $order, ['quantities' => [$orderLine => 10]])->assertOk();

        $loading = $this->loading($erp, $order)->assertCreated()->assertJsonPath('data.lines.0.quantity_ordered', '12.000')
            ->assertJsonPath('data.lines.0.quantity_approved', '10.000')->json('data');
        $line = $loading['lines'][0]['id'];
        $base = "/api/erp/dispatch/loading-orders/{$loading['id']}";

        // Never more than approved; confirming before quantities are entered is refused.
        $this->as($erp, 'storekeeper')->postJson("{$base}/confirm-loading")->assertStatus(422);
        $this->as($erp, 'storekeeper')->putJson("{$base}/loaded", ['quantities' => [$line => 11]])->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'never more'));
        $this->as($erp, 'storekeeper')->putJson("{$base}/loaded", ['quantities' => [$line => 9]])->assertOk();
        $this->assertSame(40.0, $this->onHand($erp), 'Entering quantities moves nothing.');

        // The gate pass needs a delivery note, the delivery note needs the confirmations.
        $this->as($erp, 'storekeeper')->postJson("{$base}/confirm-loading")->assertOk()->assertJsonPath('data.status', 'loaded');
        $this->as($erp, 'storekeeper')->postJson("{$base}/confirm-loading")->assertStatus(422);
        $this->as($erp, 'dispatch')->postJson("{$base}/gate-pass")->assertStatus(422);
        $this->as($erp, 'dispatch')->postJson("{$base}/delivery-note")->assertStatus(422);
        $this->as($erp, 'storekeeper')->postJson("{$base}/confirm-security", ['name' => 'Saidi'])->assertForbidden();
        $this->as($erp, 'dispatch')->postJson("{$base}/confirm-driver")->assertOk()->assertJsonPath('data.driver_confirmed_name', 'Juma Mussa');
        $this->as($erp, 'dispatch')->postJson("{$base}/confirm-security", ['name' => 'Saidi Hamisi'])->assertOk();
        $note = $this->as($erp, 'dispatch')->postJson("{$base}/delivery-note")->assertOk()->json('data');
        $this->as($erp, 'dispatch')->postJson("{$base}/gate-pass")->assertOk()->assertJsonPath('data.status', 'dispatched');

        // Stock left once, for exactly what was loaded, at loading confirmation, against cost of sales.
        $this->assertSame(31.0, $this->onHand($erp));
        $issues = StockDocument::acrossTenants()->where('source_type', 'loading_order')->where('source_id', $loading['id'])->get();
        $this->assertCount(1, $issues);
        $this->assertSame('issue', $issues[0]->type);
        $this->assertSame('cogs', $issues[0]->contra_account);
        $this->assertSame($issues[0]->id, $note['stock_document_id']);
        $this->assertSame(-9.0, (float) StockMovement::acrossTenants()->where('stock_document_id', $issues[0]->id)->sum('quantity'));
        $this->assertSame(['cogs' => [54000.0, 0.0], 'inventory' => [0.0, 54000.0]], $this->journal('StockDocument', $issues[0]->id));

        // The delivery note carries the same lines and quantities as the loading order.
        $this->assertStringStartsWith('DN-', $note['delivery_note_number']);
        $this->assertSame('9.000', $note['lines'][0]['quantity_loaded']);
        $this->assertSame('10.000', $note['lines'][0]['quantity_approved']);

        $this->as($erp, 'dispatch')->postJson("{$base}/deliver", [
            'received_by_name' => 'Rehema Said', 'received_date' => now()->toDateString(), 'quantities' => [$line => 10],
        ])->assertStatus(422);
        $this->as($erp, 'dispatch')->postJson("{$base}/deliver", [
            'received_by_name' => 'Rehema Said', 'received_date' => now()->toDateString(), 'quantities' => [$line => 9],
        ])->assertOk()->assertJsonPath('data.status', 'delivered')->assertJsonPath('data.discrepancy_status', null);

        // Four quantities, four columns, on the order line.
        $row = DB::table('sales_order_lines')->where('id', $orderLine)->first();
        $this->assertEquals([12, 10, 9, 9], [(float) $row->quantity_ordered, (float) $row->quantity_approved, (float) $row->quantity_loaded, (float) $row->quantity_received]);
        // One carton was approved but never loaded: the order stays open for it.
        $this->assertSame('ready', DB::table('sales_orders')->where('id', $order)->value('status'));
        $this->assertSame(31.0, $this->onHand($erp), 'Delivery does not move stock again.');
    }

    public function test_a_short_delivery_is_a_discrepancy_until_returned_to_stock(): void
    {
        $erp = $this->erp();
        $this->stock($erp, 20);
        $order = $this->order($erp, 'credit');
        $this->approve($erp, $order)->assertOk();
        $lo = $this->dispatchOut($erp, $order);

        $this->as($erp, 'dispatch')->postJson("{$lo['base']}/deliver", [
            'received_by_name' => 'Ally Mohamed', 'received_date' => now()->toDateString(), 'quantities' => [$lo['line'] => 8], 'remark' => 'Two cartons crushed',
        ])->assertOk()->assertJsonPath('data.discrepancy_status', 'open');
        $this->assertSame(10.0, $this->onHand($erp));
        $this->assertSame('delivered', DB::table('sales_orders')->where('id', $order)->value('status'));

        $this->as($erp, 'dispatch')->postJson("{$lo['base']}/resolve", ['decision' => 'return', 'note' => 'Back on the truck'])->assertForbidden();
        $resolved = $this->as($erp, 'warehouse_manager')->postJson("{$lo['base']}/resolve", ['decision' => 'return', 'note' => 'Driver brought them back'])
            ->assertOk()->assertJsonPath('data.discrepancy_status', 'returned')->json('data');
        $this->as($erp, 'warehouse_manager')->postJson("{$lo['base']}/resolve", ['decision' => 'return', 'note' => 'Again'])->assertStatus(422);

        $this->assertSame(12.0, $this->onHand($erp));
        $grn = StockDocument::acrossTenants()->findOrFail($resolved['return_document_id']);
        $this->assertSame(['grn', 'posted', 'loading_order', 'cogs'], [$grn->type, $grn->status, $grn->source_type, $grn->contra_account]);
        $this->assertSame(['cogs' => [0.0, 12000.0], 'inventory' => [12000.0, 0.0]], $this->journal('StockDocument', $grn->id));

        // Invoicing the delivery bills what arrived, not what left.
        $invoice = $this->invoice($erp, $order, $lo['id']);
        $this->assertEquals(8, (float) DB::table('sales_invoice_lines')->where('sales_invoice_id', $invoice)->value('quantity'));
    }

    public function test_a_short_delivery_can_be_written_off(): void
    {
        $erp = $this->erp();
        $this->stock($erp, 20);
        $order = $this->order($erp, 'credit');
        $this->approve($erp, $order)->assertOk();
        $lo = $this->dispatchOut($erp, $order);
        $this->as($erp, 'dispatch')->postJson("{$lo['base']}/deliver", [
            'received_by_name' => 'Ally Mohamed', 'received_date' => now()->toDateString(), 'quantities' => [$lo['line'] => 7],
        ])->assertOk();

        $this->as($erp, 'finance')->postJson("{$lo['base']}/resolve", ['decision' => 'write_off', 'note' => 'Stolen at Chalinze, police report RB/114/2026'])
            ->assertOk()->assertJsonPath('data.discrepancy_status', 'written_off');

        $this->assertSame(10.0, $this->onHand($erp));
        $this->assertSame(['cogs' => [0.0, 18000.0], 'transit_losses' => [18000.0, 0.0]], $this->journal('LoadingOrder', $lo['id'], 'write_off'));
    }

    public function test_an_invoice_balances_posts_once_and_a_receipt_clears_it(): void
    {
        $erp = $this->erp();
        $order = $this->order($erp, 'credit', 3, 9999.99);
        $line = DB::table('sales_order_lines')->where('sales_order_id', $order)->first();
        $this->assertEquals(29999.97, (float) $line->line_subtotal);
        $this->approve($erp, $order)->assertOk();

        $invoice = $this->invoice($erp, $order);
        $this->as($erp, 'accountant')->postJson("/api/erp/sales/invoices/{$invoice}/post")->assertStatus(422);
        $this->as($erp, 'accountant')->postJson("/api/erp/sales/orders/{$order}/invoice")->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'already been invoiced'));

        // 29,999.97 net + 5,399.99 VAT = 35,399.96
        $this->assertSame([
            'receivable' => [35399.96, 0.0], 'sales' => [0.0, 29999.97], 'vat_output' => [0.0, 5399.99],
        ], $this->journal('SalesInvoice', $invoice));
        $this->assertSame(1, DB::table('journal_entries')->where('source_type', 'SalesInvoice')->where('source_id', $invoice)->count());

        // Over-allocation is refused; the exact amount clears the invoice once verified.
        $bank = DB::table('accounts')->where('company_id', $erp['company']->id)->where('system_key', 'bank')->value('id');
        $this->as($erp, 'cashier')->postJson('/api/erp/sales/receipts', [
            'customer_id' => $erp['credit']->id, 'account_id' => $bank, 'method' => 'cash',
            'allocations' => [['sales_invoice_id' => $invoice, 'amount' => 40000]],
        ])->assertStatus(422);
        $inventory = DB::table('accounts')->where('company_id', $erp['company']->id)->where('system_key', 'inventory')->value('id');
        $this->as($erp, 'cashier')->postJson('/api/erp/sales/receipts', [
            'customer_id' => $erp['credit']->id, 'account_id' => $inventory, 'method' => 'cash',
            'allocations' => [['sales_invoice_id' => $invoice, 'amount' => 100]],
        ])->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'cash or bank account'));

        $receipt = $this->receipt($erp, $invoice, 35399.96);
        $this->assertEquals(35399.96, (float) $this->as($erp, 'finance')->getJson('/api/erp/sales/reports/aged-receivables')->json('data.totals.total'));
        $this->as($erp, 'finance')->postJson("/api/erp/sales/receipts/{$receipt}/verify")->assertOk();
        $this->as($erp, 'finance')->postJson("/api/erp/sales/receipts/{$receipt}/verify")->assertStatus(422);

        $this->assertSame(['bank' => [35399.96, 0.0], 'receivable' => [0.0, 35399.96]], $this->journal('SalesReceipt', $receipt));
        $this->assertEquals(0, (float) $this->as($erp, 'finance')->getJson('/api/erp/sales/reports/aged-receivables')->json('data.totals.total'));
        $this->as($erp, 'finance')->getJson("/api/erp/sales/invoices/{$invoice}")->assertJsonPath('data.balance', 0);

        $statement = $this->as($erp, 'finance')->getJson("/api/erp/sales/customers/{$erp['credit']->id}/statement")->assertOk()->json('data');
        $this->assertCount(2, $statement['lines']);
        $this->assertEquals(0, $statement['closing_balance']);
    }

    public function test_aged_receivables_fill_each_bucket_by_days_past_due(): void
    {
        $erp = $this->erp();
        $invoices = [];
        foreach ([0, 10, 45, 75, 120] as $late) {
            $order = $this->order($erp, 'credit', 1);
            $this->approve($erp, $order)->assertOk();
            $invoices[$late] = $this->invoice($erp, $order);
        }
        foreach ($invoices as $late => $id) {
            DB::table('sales_invoices')->where('id', $id)->update([
                'invoice_date' => now()->subDays($late + 30)->toDateString(), 'due_date' => now()->subDays($late)->toDateString(),
            ]);
        }

        $aged = $this->as($erp, 'ceo')->getJson('/api/erp/sales/reports/aged-receivables')->assertOk()->json('data');
        $this->assertEquals(
            ['current' => 11800, 'd1_30' => 11800, 'd31_60' => 11800, 'd61_90' => 11800, 'd90_plus' => 11800, 'total' => 59000],
            $aged['totals'],
        );
    }

    public function test_a_return_credits_revenue_and_vat_and_brings_the_goods_back(): void
    {
        $erp = $this->erp();
        $this->stock($erp, 20);
        $order = $this->order($erp, 'credit');
        $this->approve($erp, $order)->assertOk();
        $lo = $this->dispatchOut($erp, $order);
        $this->as($erp, 'dispatch')->postJson("{$lo['base']}/deliver", ['received_by_name' => 'Ally', 'received_date' => now()->toDateString(), 'quantities' => [$lo['line'] => 10]])->assertOk();
        $invoice = $this->invoice($erp, $order, $lo['id']);
        $invoiceLine = DB::table('sales_invoice_lines')->where('sales_invoice_id', $invoice)->value('id');

        $this->as($erp, 'sales')->postJson('/api/erp/sales/credit-notes', [
            'sales_invoice_id' => $invoice, 'reason' => 'Leaking', 'lines' => [['sales_invoice_line_id' => $invoiceLine, 'quantity' => 2]],
        ])->assertForbidden();
        $this->as($erp, 'finance')->postJson('/api/erp/sales/credit-notes', [
            'sales_invoice_id' => $invoice, 'reason' => 'Leaking', 'lines' => [['sales_invoice_line_id' => $invoiceLine, 'quantity' => 11]],
        ])->assertStatus(422);

        $note = $this->as($erp, 'finance')->postJson('/api/erp/sales/credit-notes', [
            'sales_invoice_id' => $invoice, 'reason' => 'Two cartons leaking', 'return_to_stock' => true, 'warehouse_id' => $erp['main']->id,
            'lines' => [['sales_invoice_line_id' => $invoiceLine, 'quantity' => 2]],
        ])->assertCreated()->json('data.id');
        $this->as($erp, 'finance')->postJson("/api/erp/sales/credit-notes/{$note}/post")->assertOk();
        $this->as($erp, 'finance')->postJson("/api/erp/sales/credit-notes/{$note}/post")->assertStatus(422);

        $this->assertSame(['receivable' => [0.0, 23600.0], 'sales_returns' => [20000.0, 0.0], 'vat_output' => [3600.0, 0.0]], $this->journal('SalesCreditNote', $note));
        $this->assertSame(12.0, $this->onHand($erp));
        $this->as($erp, 'finance')->getJson("/api/erp/sales/invoices/{$invoice}")->assertJsonPath('data.balance', 94400);
    }

    public function test_a_customer_price_list_sets_the_order_price(): void
    {
        $erp = $this->erp();
        $list = $this->as($erp, 'finance')->postJson('/api/erp/sales/price-lists', ['code' => 'WHOLESALE', 'name' => 'Wholesale'])->assertCreated()->json('data.id');
        $this->as($erp, 'finance')->putJson("/api/erp/sales/price-lists/{$list}/items", ['items' => [
            ['product_id' => $erp['product']->id, 'unit_price' => 8000, 'effective_from' => now()->subMonth()->toDateString()],
            ['product_id' => $erp['product']->id, 'unit_price' => 8200, 'effective_from' => now()->addWeek()->toDateString()],
        ]])->assertOk();
        $this->as($erp, 'finance')->putJson("/api/erp/sales/price-lists/{$list}/customers", ['customer_ids' => [$erp['credit']->id]])->assertOk();
        $this->as($erp, 'sales')->putJson("/api/erp/sales/price-lists/{$list}/items", ['items' => []])->assertForbidden();

        $order = $this->as($erp, 'sales')->postJson('/api/erp/sales/orders', [
            'customer_id' => $erp['credit']->id, 'lines' => [['product_id' => $erp['product']->id, 'quantity' => 2]],
        ])->assertCreated()->json('data');
        $this->assertEquals(8000, (float) $order['lines'][0]['unit_price']);
        $this->assertEquals(18, (float) $order['lines'][0]['tax_rate']);

        // Without a list, the product's own price.
        $other = $this->as($erp, 'sales')->postJson('/api/erp/sales/orders', [
            'customer_id' => $erp['prepay']->id, 'lines' => [['product_id' => $erp['product']->id, 'quantity' => 2]],
        ])->json('data');
        $this->assertEquals(9000, (float) $other['lines'][0]['unit_price']);
    }

    public function test_a_quotation_converts_into_an_order_once(): void
    {
        $erp = $this->erp();
        $quote = $this->as($erp, 'sales')->postJson('/api/erp/sales/quotations', [
            'customer_id' => $erp['credit']->id, 'lines' => [['product_id' => $erp['product']->id, 'quantity' => 5, 'discount_percent' => 10]],
        ])->assertCreated()->assertJsonPath('data.total', '47790.00')->json('data.id');

        $this->as($erp, 'sales')->postJson("/api/erp/sales/quotations/{$quote}/send")->assertOk();
        $order = $this->as($erp, 'sales')->postJson("/api/erp/sales/quotations/{$quote}/convert")->assertCreated()
            ->assertJsonPath('data.status', 'draft')->assertJsonPath('data.total', '47790.00')->json('data.id');
        $this->as($erp, 'sales')->postJson("/api/erp/sales/quotations/{$quote}/convert")->assertStatus(422);
        $this->assertSame($order, DB::table('sales_quotations')->where('id', $quote)->value('sales_order_id'));
    }

    public function test_roles_are_refused_what_they_may_not_do(): void
    {
        $erp = $this->erp();
        $this->stock($erp, 20);
        $order = $this->order($erp, 'credit');

        $this->as($erp, 'sales')->postJson("/api/erp/sales/orders/{$order}/approve")->assertForbidden();
        $this->as($erp, 'storekeeper')->getJson('/api/erp/sales/orders')->assertForbidden();
        $this->as($erp, 'employee')->getJson('/api/erp/dispatch/loading-orders')->assertForbidden();
        $this->approve($erp, $order)->assertOk();
        $this->as($erp, 'sales')->postJson("/api/erp/sales/orders/{$order}/invoice")->assertForbidden();
        $this->as($erp, 'sales')->postJson('/api/erp/dispatch/loading-orders', ['sales_order_id' => $order, 'warehouse_id' => $erp['main']->id])->assertForbidden();
        $this->as($erp, 'cashier')->getJson('/api/erp/dispatch/verification')->assertForbidden();
        $this->as($erp, 'finance')->getJson('/api/erp/dispatch/verification')->assertOk();

        $lo = $this->loading($erp, $order)->assertCreated()->json('data');
        $this->as($erp, 'accountant')->postJson("/api/erp/dispatch/loading-orders/{$lo['id']}/confirm-loading")->assertForbidden();
        $this->as($erp, 'storekeeper')->postJson("/api/erp/dispatch/loading-orders/{$lo['id']}/gate-pass")->assertForbidden();
        $this->as($erp, 'storekeeper')->postJson("/api/erp/dispatch/loading-orders/{$lo['id']}/deliver", ['received_by_name' => 'X', 'received_date' => now()->toDateString(), 'quantities' => []])->assertForbidden();
    }

    public function test_the_modules_must_be_switched_on(): void
    {
        $erp = $this->erp();
        $erp['company']->forceFill(['modules' => ['vouchflow', 'inventory', 'sales', 'accounting']])->save();

        $this->as($erp, 'dispatch')->getJson('/api/erp/dispatch/loading-orders')->assertForbidden()->assertJsonPath('code', 'module_disabled');
        $this->as($erp, 'sales')->getJson('/api/erp/sales/orders')->assertOk();
    }

    public function test_another_companys_sales_and_dispatch_records_are_invisible(): void
    {
        $mine = $this->erp('Maji Bora');
        $theirs = $this->erp('Kilimanjaro Springs');
        $this->stock($theirs, 20);
        $order = $this->order($theirs, 'credit');
        $this->approve($theirs, $order)->assertOk();
        $invoice = $this->invoice($theirs, $order);
        $lo = $this->loading($theirs, $order)->assertCreated()->json('data.id');
        $receipt = $this->receipt($theirs, $invoice, 1000);

        $this->as($mine, 'finance')->getJson("/api/erp/sales/orders/{$order}")->assertNotFound();
        $this->as($mine, 'finance')->postJson("/api/erp/sales/orders/{$order}/cancel")->assertNotFound();
        $this->as($mine, 'finance')->getJson("/api/erp/sales/invoices/{$invoice}")->assertNotFound();
        $this->as($mine, 'finance')->postJson("/api/erp/sales/receipts/{$receipt}/verify")->assertNotFound();
        $this->as($mine, 'warehouse_manager')->getJson("/api/erp/dispatch/loading-orders/{$lo}")->assertNotFound();
        $this->as($mine, 'warehouse_manager')->postJson("/api/erp/dispatch/loading-orders/{$lo}/cancel")->assertNotFound();
        $this->as($mine, 'finance')->getJson("/api/erp/sales/customers/{$theirs['credit']->id}/statement")->assertNotFound();
        $this->as($mine, 'dispatch')->postJson('/api/erp/dispatch/loading-orders', ['sales_order_id' => $order, 'warehouse_id' => $mine['main']->id])->assertStatus(422);
        $this->as($mine, 'finance')->getJson('/api/erp/sales/orders')->assertOk()->assertJsonPath('total', 0);
        $this->as($mine, 'finance')->getJson('/api/erp/sales/reports/aged-receivables')->assertJsonPath('data.totals.total', 0);
    }

    public function test_batch_tracked_goods_leave_first_expiry_first_across_batches(): void
    {
        $erp = $this->erp();
        $product = Product::acrossTenants()->findOrFail($erp['product']->id);
        $product->update(['track_batches' => true, 'track_expiry' => true]);
        foreach ([['B-LATE', 12], ['B-SOON', 3]] as [$batch, $months]) {
            $id = $this->as($erp, 'storekeeper')->postJson('/api/erp/stock-documents', [
                'type' => 'grn', 'warehouse_id' => $erp['main']->id,
                'lines' => [['product_id' => $product->id, 'quantity' => 6, 'unit_cost' => 6000, 'batch_number' => $batch, 'expiry_date' => now()->addMonths($months)->toDateString()]],
            ])->assertCreated()->json('data.id');
            $this->as($erp, 'warehouse_manager')->postJson("/api/erp/stock-documents/{$id}/post")->assertOk();
        }

        $order = $this->order($erp, 'credit', 8);
        $this->approve($erp, $order)->assertOk();
        $lo = $this->dispatchOut($erp, $order);
        $this->as($erp, 'dispatch')->postJson("{$lo['base']}/deliver", ['received_by_name' => 'Ally', 'received_date' => now()->toDateString(), 'quantities' => [$lo['line'] => 7]])->assertOk();
        $this->as($erp, 'warehouse_manager')->postJson("{$lo['base']}/resolve", ['decision' => 'return', 'note' => 'One returned'])->assertOk();

        $left = StockBalance::acrossTenants()->where('product_id', $product->id)->pluck('quantity', 'batch_number')->map(fn ($q) => (float) $q)->all();
        $this->assertEquals(['B-LATE' => 4.0, 'B-SOON' => 1.0], $left);
    }

    public function test_every_screen_endpoint_answers(): void
    {
        $erp = $this->erp();
        $this->stock($erp, 20);
        $quote = $this->as($erp, 'sales')->postJson('/api/erp/sales/quotations', [
            'customer_id' => $erp['credit']->id, 'lines' => [['product_id' => $erp['product']->id, 'quantity' => 1]],
        ])->json('data.id');
        $order = $this->order($erp, 'credit');
        $this->as($erp, 'finance')->getJson("/api/erp/sales/orders/{$order}")->assertOk()->assertJsonPath('data.policy_preview.passed', true);
        $this->approve($erp, $order)->assertOk();
        $lo = $this->dispatchOut($erp, $order);
        $this->as($erp, 'dispatch')->postJson("{$lo['base']}/deliver", ['received_by_name' => 'Ally', 'received_date' => now()->toDateString(), 'quantities' => [$lo['line'] => 10]])->assertOk();
        $invoice = $this->invoice($erp, $order, $lo['id']);
        $this->receipt($erp, $invoice, 1000);

        foreach ([
            '/api/erp/sales/overview', '/api/erp/sales/lookups', "/api/erp/sales/prices?customer_id={$erp['credit']->id}",
            '/api/erp/sales/quotations', "/api/erp/sales/quotations/{$quote}", '/api/erp/sales/orders', '/api/erp/sales/orders/counts',
            "/api/erp/sales/orders/{$order}", '/api/erp/sales/invoices?open_only=1', "/api/erp/sales/invoices/{$invoice}",
            '/api/erp/sales/receipts', '/api/erp/sales/credit-notes', '/api/erp/sales/price-lists',
            "/api/erp/sales/customers/{$erp['credit']->id}/statement", '/api/erp/sales/reports/aged-receivables',
            '/api/erp/sales/reports/sales?group=customer', '/api/erp/sales/reports/sales?group=product', '/api/erp/sales/reports/sales?group=month',
            '/api/erp/dispatch/verification', '/api/erp/dispatch/lookups', '/api/erp/dispatch/loading-orders?stage=gate_passes',
            "/api/erp/dispatch/loading-orders/{$lo['id']}",
        ] as $url) {
            $this->as($erp, 'finance')->getJson($url)->assertOk();
        }

        $this->as($erp, 'finance')->getJson('/api/erp/sales/overview')->assertJsonPath('data.awaiting_verification', 1);
        $this->as($erp, 'finance')->getJson('/api/erp/sales/reports/sales?group=product')->assertJsonPath('data.rows.0.net', 100000);
        $this->as($erp, 'finance')->getJson('/api/erp/dispatch/verification')->assertJsonCount(1, 'data.receipts');
    }
}
