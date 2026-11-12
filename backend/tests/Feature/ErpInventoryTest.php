<?php

namespace Tests\Feature;

use App\Models\Erp\JournalEntry;
use App\Models\Erp\StockBalance;
use App\Models\Erp\StockMovement;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use LogicException;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * The inventory ledger: stock moves only when a document is posted, exactly
 * once, never below zero by default, and always with a matching ledger entry.
 * Acceptance criteria 1, 2 and 14 of the requirements live here.
 */
class ErpInventoryTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function document(array $erp, string $type, array $lines, array $header = [], string $as = 'storekeeper'): TestResponse
    {
        return $this->actingAs($erp[$as], 'sanctum')->postJson('/api/erp/stock-documents', [
            'type' => $type,
            'warehouse_id' => $erp['main']->id,
            ...$header,
            'lines' => $lines,
        ]);
    }

    private function postDocument(array $erp, int $id, string $as = 'warehouse_manager'): TestResponse
    {
        return $this->actingAs($erp[$as], 'sanctum')->postJson("/api/erp/stock-documents/{$id}/post");
    }

    private function onHand(array $erp, string $warehouse = 'main'): float
    {
        return (float) StockBalance::acrossTenants()
            ->where('product_id', $erp['product']->id)
            ->where('warehouse_id', $erp[$warehouse]->id)
            ->sum('quantity');
    }

    private function receive(array $erp, float $quantity = 100, float $cost = 6000): int
    {
        $id = $this->document($erp, 'grn', [['product_id' => $erp['product']->id, 'quantity' => $quantity, 'unit_cost' => $cost]], [
            'supplier_id' => $erp['supplier']->id,
        ])->assertCreated()->json('data.id');

        $this->postDocument($erp, $id)->assertOk();

        return $id;
    }

    public function test_stock_rises_only_once_a_grn_is_posted(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));

        $id = $this->document($erp, 'grn', [['product_id' => $erp['product']->id, 'quantity' => 120, 'unit_cost' => 6000]], [
            'supplier_id' => $erp['supplier']->id,
        ])->assertCreated()->assertJsonPath('data.status', 'draft')->json('data.id');

        $this->assertSame(0.0, $this->onHand($erp), 'A draft GRN must not move stock.');

        $this->postDocument($erp, $id)->assertOk()->assertJsonPath('data.status', 'posted');

        $this->assertSame(120.0, $this->onHand($erp));
        $this->assertSame(1, StockMovement::acrossTenants()->where('stock_document_id', $id)->count());
    }

    public function test_a_document_cannot_be_posted_twice(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        $id = $this->receive($erp, 50);

        $this->postDocument($erp, $id)->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'posted'));

        $this->assertSame(50.0, $this->onHand($erp));
        $this->assertSame(1, JournalEntry::acrossTenants()->where('source_type', 'StockDocument')->where('source_id', $id)->count());
    }

    public function test_an_issue_reduces_stock_once_and_refuses_to_go_negative(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        $this->receive($erp, 30);

        $issue = $this->document($erp, 'issue', [['product_id' => $erp['product']->id, 'quantity' => 20]])->json('data.id');
        $this->postDocument($erp, $issue)->assertOk();
        $this->postDocument($erp, $issue)->assertStatus(422);
        $this->assertSame(10.0, $this->onHand($erp));

        $tooMuch = $this->document($erp, 'issue', [['product_id' => $erp['product']->id, 'quantity' => 11]])->json('data.id');
        $this->postDocument($erp, $tooMuch)
            ->assertStatus(422)
            ->assertJsonPath('message', 'Not enough Water 500ml x24 in Main store: 10 on hand, 11 needed.');

        $this->assertSame(10.0, $this->onHand($erp), 'A refused posting must leave no trace.');
        $this->assertSame('draft', $this->getJson("/api/erp/stock-documents/{$tooMuch}")->json('data.status'));
    }

    public function test_negative_stock_is_allowed_only_when_the_company_policy_says_so(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Duka Huru'), 'retail', ['allow_negative_stock' => true]);

        $issue = $this->document($erp, 'issue', [['product_id' => $erp['product']->id, 'quantity' => 3]])->json('data.id');
        $this->postDocument($erp, $issue)->assertOk();

        $this->assertSame(-3.0, $this->onHand($erp));
    }

    public function test_a_transfer_moves_stock_between_places_without_touching_the_ledger_value(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        $this->receive($erp, 40, 5000);

        $id = $this->document($erp, 'transfer', [['product_id' => $erp['product']->id, 'quantity' => 15]], [
            'to_warehouse_id' => $erp['depot']->id,
        ])->assertCreated()->json('data.id');
        $this->postDocument($erp, $id)->assertOk();

        $this->assertSame(25.0, $this->onHand($erp));
        $this->assertSame(15.0, $this->onHand($erp, 'depot'));
        $this->assertSame(0, JournalEntry::acrossTenants()->where('source_type', 'StockDocument')->where('source_id', $id)->count());

        $depotCost = StockBalance::acrossTenants()->where('warehouse_id', $erp['depot']->id)->value('average_cost');
        $this->assertEquals(5000, (float) $depotCost, 'Stock arrives at the cost it left at.');
    }

    public function test_a_count_posts_only_the_variance(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        $this->receive($erp, 40);

        $id = $this->document($erp, 'count', [['product_id' => $erp['product']->id, 'quantity' => 37]])->json('data.id');
        $this->postDocument($erp, $id)->assertOk()
            ->assertJsonPath('data.lines.0.system_quantity', '40.0000')
            ->assertJsonPath('data.movements.0.quantity', '-3.0000');

        $this->assertSame(37.0, $this->onHand($erp));
    }

    public function test_weighted_average_cost_follows_each_receipt(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        $this->receive($erp, 10, 5000);
        $this->receive($erp, 30, 7000);

        $balance = StockBalance::acrossTenants()->where('product_id', $erp['product']->id)->first();

        $this->assertEquals(6500, (float) $balance->average_cost);
        $this->assertEquals(260000, $this->actingAs($erp['admin'], 'sanctum')->getJson('/api/erp/stock/valuation')->json('data.total'));
    }

    public function test_reversing_a_grn_takes_the_stock_and_the_ledger_entry_back_out(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        $id = $this->receive($erp, 20, 6000);

        $this->actingAs($erp['warehouse_manager'], 'sanctum')
            ->postJson("/api/erp/stock-documents/{$id}/reverse", ['reason' => 'Wrong supplier delivery'])
            ->assertOk();

        $this->assertSame(0.0, $this->onHand($erp));
        $this->assertSame('reversed', $this->getJson("/api/erp/stock-documents/{$id}")->json('data.status'));

        $balance = $this->actingAs($erp['admin'], 'sanctum')->getJson('/api/erp/trial-balance')->json('data');
        $this->assertTrue($balance['balanced']);
        $inventory = collect($balance['rows'])->firstWhere('code', '1400');
        $this->assertEquals(0, $inventory['balance']);
    }

    public function test_a_consumed_receipt_cannot_be_reversed_into_negative_stock(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        $grn = $this->receive($erp, 10);
        $issue = $this->document($erp, 'issue', [['product_id' => $erp['product']->id, 'quantity' => 6]])->json('data.id');
        $this->postDocument($erp, $issue)->assertOk();

        $this->actingAs($erp['warehouse_manager'], 'sanctum')
            ->postJson("/api/erp/stock-documents/{$grn}/reverse", ['reason' => 'Supplier recall'])
            ->assertStatus(422);

        $this->assertSame(4.0, $this->onHand($erp));
    }

    public function test_posting_writes_a_balanced_journal_for_each_stock_document(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        $this->receive($erp, 10, 6000);
        $issue = $this->document($erp, 'issue', [['product_id' => $erp['product']->id, 'quantity' => 4]])->json('data.id');
        $this->postDocument($erp, $issue)->assertOk();

        $tb = $this->actingAs($erp['admin'], 'sanctum')->getJson('/api/erp/trial-balance')->assertOk()->json('data');
        $rows = collect($tb['rows'])->keyBy('code');

        $this->assertTrue($tb['balanced']);
        $this->assertEquals(36000, $rows['1400']['balance'], 'Inventory: 60,000 in, 24,000 out.');
        $this->assertEquals(60000, $rows['2150']['balance'], 'Goods received, not yet invoiced.');
        $this->assertEquals(24000, $rows['5200']['balance'], 'Stock issued to operations.');
    }

    public function test_batch_and_expiry_are_required_for_products_that_track_them(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Afya Pharmacy'), 'pharmacy');
        $erp['product']->update(['track_batches' => true, 'track_expiry' => true]);

        $this->document($erp, 'grn', [['product_id' => $erp['product']->id, 'quantity' => 5, 'unit_cost' => 100]])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'batch number'));

        $this->document($erp, 'grn', [['product_id' => $erp['product']->id, 'quantity' => 5, 'unit_cost' => 100, 'batch_number' => 'B1']])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'expiry date'));

        $this->document($erp, 'grn', [[
            'product_id' => $erp['product']->id, 'quantity' => 5, 'unit_cost' => 100,
            'batch_number' => 'B1', 'expiry_date' => now()->addDays(20)->toDateString(),
        ]])->assertCreated();
    }

    public function test_whole_units_refuse_fractions(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));

        $this->document($erp, 'grn', [['product_id' => $erp['product']->id, 'quantity' => 2.5, 'unit_cost' => 100]])
            ->assertStatus(422)->assertJsonPath('message', 'Water 500ml x24 is counted in whole Cartons.');
    }

    public function test_the_ledger_is_append_only(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        $this->receive($erp, 5);

        $movement = StockMovement::acrossTenants()->firstOrFail();

        $this->expectException(LogicException::class);
        $movement->update(['quantity' => 500]);
    }

    public function test_low_stock_and_expiry_alerts(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        $this->receive($erp, 8);

        $this->actingAs($erp['storekeeper'], 'sanctum')->getJson('/api/erp/stock/alerts')
            ->assertOk()
            ->assertJsonPath('data.low_stock.0.sku', 'WTR-500');
    }
}
