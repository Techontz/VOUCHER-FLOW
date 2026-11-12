<?php

namespace Tests\Feature;

use App\Models\Erp\Account;
use App\Models\Erp\JournalEntry;
use App\Models\Erp\JournalLine;
use App\Models\Erp\Product;
use App\Models\Erp\Production\Bom;
use App\Models\Erp\Production\ProductionOrder;
use App\Models\Erp\StockBalance;
use App\Models\Erp\StockDocument;
use App\Models\Erp\StockMovement;
use App\Models\Erp\Unit;
use App\Models\User;
use App\Services\Erp\StockDocuments;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Production: materials go to work in progress exactly once, released output
 * comes back out of it at actual cost, quality-rejected output never reaches
 * stock, a closed order leaves nothing on work in progress, and batches can
 * be traced both ways.
 */
class ErpProductionTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    /** @return array<string, mixed> */
    private function factory(string $name = 'Maji Safi'): array
    {
        $erp = $this->setUpErp($this->makeTenant($name), 'beverage');
        $company = $erp['company'];

        return app(TenantContext::class)->forCompany($company, function () use ($erp, $company) {
            $slug = $company->slug;
            $pcs = Unit::where('code', 'PCS')->firstOrFail();
            $ctn = Unit::where('code', 'CTN')->firstOrFail();

            $preform = Product::create(['company_id' => $company->id, 'sku' => 'RM-PRF', 'name' => 'PET preform 28g', 'type' => 'raw_material', 'unit_id' => $pcs->id, 'cost_price' => 100, 'track_batches' => true]);
            $label = Product::create(['company_id' => $company->id, 'sku' => 'PK-LBL', 'name' => 'Label 500ml', 'type' => 'packaging', 'unit_id' => $pcs->id, 'cost_price' => 10]);
            $water = Product::create(['company_id' => $company->id, 'sku' => 'FG-W500', 'name' => 'Water 500ml x24', 'type' => 'finished_good', 'unit_id' => $ctn->id, 'cost_price' => 3000, 'sale_price' => 8500, 'track_batches' => true, 'track_expiry' => true]);

            $production = User::create([
                'company_id' => $company->id, 'name' => "Production {$slug}", 'email' => "production@{$slug}.test",
                'password' => 'Password123!', 'role' => User::ROLE_PRODUCTION_MANAGER, 'status' => 'active',
            ]);

            $documents = app(StockDocuments::class);
            $opening = $documents->create('opening', ['warehouse_id' => $erp['main']->id, 'document_date' => now()->subDays(5)->toDateString()], [
                ['product_id' => $preform->id, 'quantity' => 1000, 'unit_cost' => 100, 'batch_number' => 'P1', 'expiry_date' => now()->addMonths(2)->toDateString()],
                ['product_id' => $preform->id, 'quantity' => 2000, 'unit_cost' => 100, 'batch_number' => 'P2', 'expiry_date' => now()->addMonths(6)->toDateString()],
                ['product_id' => $label->id, 'quantity' => 5000, 'unit_cost' => 10],
            ], $erp['admin']);
            $documents->post($opening, $erp['admin']);

            return [...$erp, 'preform' => $preform, 'label' => $label, 'water' => $water, 'production' => $production];
        });
    }

    private function bom(array $erp): int
    {
        return $this->actingAs($erp['production'], 'sanctum')->postJson('/api/erp/production/boms', [
            'product_id' => $erp['water']->id,
            'output_quantity' => 100,
            'labour_cost' => 20000,
            'overhead_cost' => 10000,
            'lines' => [
                ['product_id' => $erp['preform']->id, 'quantity' => 2400, 'scrap_percent' => 2],
                ['product_id' => $erp['label']->id, 'quantity' => 2400, 'scrap_percent' => 1],
            ],
        ])->assertCreated()->assertJsonPath('data.is_active', true)->json('data.id');
    }

    private function releasedOrder(array $erp, float $quantity = 100): int
    {
        $this->bom($erp);

        $id = $this->actingAs($erp['production'], 'sanctum')->postJson('/api/erp/production/orders', [
            'product_id' => $erp['water']->id,
            'planned_quantity' => $quantity,
            'materials_warehouse_id' => $erp['main']->id,
            'output_warehouse_id' => $erp['depot']->id,
            'planned_start' => now()->toDateString(),
            'planned_end' => now()->addDay()->toDateString(),
        ])->assertCreated()->assertJsonPath('data.status', 'planned')->json('data.id');

        $this->postJson("/api/erp/production/orders/{$id}/release")->assertOk()->assertJsonPath('data.status', 'released');

        return $id;
    }

    private function issue(array $erp, int $order, array $lines, string $as = 'storekeeper'): TestResponse
    {
        return $this->actingAs($erp[$as], 'sanctum')->postJson("/api/erp/production/orders/{$order}/issue", ['lines' => $lines]);
    }

    private function issueAll(array $erp, int $order): void
    {
        $this->issue($erp, $order, [
            ['product_id' => $erp['preform']->id, 'quantity' => 2448],
            ['product_id' => $erp['label']->id, 'quantity' => 2424],
        ])->assertCreated();
    }

    private function receive(array $erp, int $order, array $data = []): int
    {
        return $this->actingAs($erp['storekeeper'], 'sanctum')->postJson("/api/erp/production/orders/{$order}/receipts", [
            'produced_quantity' => 100, 'good_quantity' => 98, 'rejected_quantity' => 1, 'wastage_quantity' => 1,
            'batch_number' => 'W500-A1', 'expiry_date' => now()->addYear()->toDateString(), 'is_final' => true,
            ...$data,
        ])->assertCreated()->assertJsonPath('data.status', 'pending_qc')->json('data.id');
    }

    private function qc(array $erp, int $receipt, string $decision, bool $passed = true): TestResponse
    {
        return $this->actingAs($erp['production'], 'sanctum')->postJson("/api/erp/production/receipts/{$receipt}/qc", [
            'decision' => $decision,
            'parameters' => [
                ['name' => 'pH', 'target' => '6.5 to 8.5', 'value' => '7.2', 'passed' => true],
                ['name' => 'Cap torque', 'target' => '12 to 18 in-lb', 'value' => $passed ? '15' : '9', 'passed' => $passed],
            ],
        ]);
    }

    private function onHand(array $erp, Product $product, string $warehouse, ?string $batch = null): float
    {
        return (float) StockBalance::acrossTenants()->where('product_id', $product->id)->where('warehouse_id', $erp[$warehouse]->id)
            ->when($batch !== null, fn ($q) => $q->where('batch_number', $batch))->sum('quantity');
    }

    /** Work in progress for one company: debits less credits on the wip account. */
    private function wip(array $erp): float
    {
        $account = Account::acrossTenants()->where('company_id', $erp['company']->id)->where('system_key', 'wip')->firstOrFail();

        return round((float) JournalLine::query()->where('account_id', $account->id)->sum('debit')
            - (float) JournalLine::query()->where('account_id', $account->id)->sum('credit'), 2);
    }

    private function assertJournalsBalance(array $erp): void
    {
        $entries = JournalEntry::acrossTenants()->where('company_id', $erp['company']->id)->with('lines')->get();
        $this->assertNotEmpty($entries);

        foreach ($entries as $entry) {
            $this->assertSame(
                (int) round($entry->lines->sum('debit') * 100),
                (int) round($entry->lines->sum('credit') * 100),
                "Journal {$entry->number} must balance.",
            );
        }
    }

    public function test_issuing_materials_moves_stock_once_and_charges_work_in_progress(): void
    {
        $erp = $this->factory();
        $order = $this->releasedOrder($erp);

        $document = $this->issue($erp, $order, [
            ['product_id' => $erp['preform']->id, 'quantity' => 1500],
            ['product_id' => $erp['label']->id, 'quantity' => 1500],
        ])->assertCreated()->assertJsonPath('data.status', 'posted')->json('data.id');

        // Unnamed batches are taken earliest expiry first: all of P1, then P2.
        $this->assertSame(0.0, $this->onHand($erp, $erp['preform'], 'main', 'P1'));
        $this->assertSame(1500.0, $this->onHand($erp, $erp['preform'], 'main', 'P2'));
        $this->assertSame(3500.0, $this->onHand($erp, $erp['label'], 'main'));
        $this->assertSame(3, StockMovement::acrossTenants()->where('stock_document_id', $document)->count());

        $stockDocument = StockDocument::acrossTenants()->findOrFail($document);
        $this->assertSame('production_order', $stockDocument->source_type);
        $this->assertSame($order, (int) $stockDocument->source_id);

        $entry = JournalEntry::acrossTenants()->where('source_type', 'StockDocument')->where('source_id', $document)->with('lines.account')->sole();
        $this->assertSame(165000.0, (float) $entry->total);
        $this->assertSame('wip', $entry->lines->firstWhere('debit', '>', 0)->account->system_key);
        $this->assertSame('inventory', $entry->lines->firstWhere('credit', '>', 0)->account->system_key);

        // Posting the same document again is refused by the stock ledger.
        $this->actingAs($erp['warehouse_manager'], 'sanctum')->postJson("/api/erp/stock-documents/{$document}/post")->assertStatus(422);
        $this->assertSame(3500.0, $this->onHand($erp, $erp['label'], 'main'));

        // An additional issue adds to the order; asking for more than is on hand moves nothing.
        $this->issue($erp, $order, [['product_id' => $erp['label']->id, 'quantity' => 924]])->assertCreated();
        $this->issue($erp, $order, [['product_id' => $erp['preform']->id, 'quantity' => 1501]])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'Not enough PET preform 28g'));
        $this->assertSame(1500.0, $this->onHand($erp, $erp['preform'], 'main'));

        $show = $this->actingAs($erp['production'], 'sanctum')->getJson("/api/erp/production/orders/{$order}")->assertOk()
            ->assertJsonPath('data.status', 'in_progress')
            ->assertJsonPath('data.material_cost', '174240.00');
        $this->assertEqualsWithDelta(2424, $show->json('data.requirements.1.issued_quantity'), 0.001);
        $this->assertEqualsWithDelta(0, $show->json('data.requirements.1.remaining_quantity'), 0.001);
        $this->assertSame(174240.0, $this->wip($erp));
        $this->assertJournalsBalance($erp);
    }

    public function test_materials_are_issued_only_to_a_released_order_and_only_its_components(): void
    {
        $erp = $this->factory();
        $this->bom($erp);

        $planned = $this->actingAs($erp['production'], 'sanctum')->postJson('/api/erp/production/orders', [
            'product_id' => $erp['water']->id, 'planned_quantity' => 50,
            'materials_warehouse_id' => $erp['main']->id, 'output_warehouse_id' => $erp['depot']->id,
            'planned_start' => now()->toDateString(), 'planned_end' => now()->toDateString(),
        ])->json('data.id');

        $this->issue($erp, $planned, [['product_id' => $erp['label']->id, 'quantity' => 10]])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'released'));

        $this->actingAs($erp['production'], 'sanctum')->postJson("/api/erp/production/orders/{$planned}/release")->assertOk();
        $this->issue($erp, $planned, [['product_id' => $erp['water']->id, 'quantity' => 1]])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'not a component'));

        $this->assertSame(0, StockDocument::acrossTenants()->where('source_type', 'production_order')->count());
    }

    public function test_released_output_enters_stock_at_actual_cost_and_a_closed_order_leaves_no_work_in_progress(): void
    {
        $erp = $this->factory();
        $order = $this->releasedOrder($erp);
        $this->issueAll($erp, $order);

        $receipt = $this->receive($erp, $order);
        $this->assertSame(0.0, $this->onHand($erp, $erp['water'], 'depot'), 'Output waits for its quality check.');

        $this->qc($erp, $receipt, 'release')->assertCreated();

        // Materials 2448 x 100 + 2424 x 10 = 269,040; labour and overhead 30,000; 98 good cartons.
        $this->assertSame(98.0, $this->onHand($erp, $erp['water'], 'depot', 'W500-A1'));
        $grn = StockDocument::acrossTenants()->where('source_type', 'production_order')->where('type', 'grn')->sole();
        $this->assertSame('wip', $grn->contra_account);
        $movement = StockMovement::acrossTenants()->where('stock_document_id', $grn->id)->sole();
        $this->assertSame('3051.43', $movement->unit_cost);

        $grnEntry = JournalEntry::acrossTenants()->where('source_type', 'StockDocument')->where('source_id', $grn->id)->with('lines.account')->sole();
        $this->assertSame('inventory', $grnEntry->lines->firstWhere('debit', '>', 0)->account->system_key);
        $this->assertSame('wip', $grnEntry->lines->firstWhere('credit', '>', 0)->account->system_key);

        // Only rounding is left on work in progress before the close.
        $this->assertEqualsWithDelta(0, $this->wip($erp), 0.5);

        $this->actingAs($erp['production'], 'sanctum')->getJson("/api/erp/production/orders/{$order}")
            ->assertJsonPath('data.status', 'completed')
            ->assertJsonPath('data.costing.actual_total', 299040)
            ->assertJsonPath('data.costing.actual_unit_cost', 3051.43);

        $this->actingAs($erp['accountant'], 'sanctum')->postJson("/api/erp/production/orders/{$order}/close")
            ->assertOk()->assertJsonPath('data.status', 'closed')->assertJsonPath('data.variance_value', '-0.14');

        $this->assertSame(0.0, $this->wip($erp));
        $this->assertSame(1, JournalEntry::acrossTenants()->where('source_type', 'ProductionOrder')->where('source_id', $order)->count());

        $this->actingAs($erp['accountant'], 'sanctum')->postJson("/api/erp/production/orders/{$order}/close")->assertStatus(422);
        $this->assertSame(1, JournalEntry::acrossTenants()->where('source_type', 'ProductionOrder')->where('source_id', $order)->count());
        $this->assertJournalsBalance($erp);
    }

    public function test_quality_rejected_output_never_enters_stock_and_its_cost_goes_to_variance(): void
    {
        $erp = $this->factory();
        $order = $this->releasedOrder($erp);
        $this->issueAll($erp, $order);
        $receipt = $this->receive($erp, $order);

        $this->qc($erp, $receipt, 'release', passed: false)
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'Cap torque failed'));

        $this->qc($erp, $receipt, 'reject', passed: false)->assertCreated()->assertJsonPath('data.decision', 'reject');
        $this->qc($erp, $receipt, 'release')->assertStatus(422);

        $this->assertSame(0.0, $this->onHand($erp, $erp['water'], 'depot'));
        $this->assertSame(0, StockDocument::acrossTenants()->where('source_type', 'production_order')->where('type', 'grn')->count());

        $this->actingAs($erp['production'], 'sanctum')->getJson("/api/erp/production/orders/{$order}")
            ->assertJsonPath('data.status', 'completed')
            ->assertJsonPath('data.released_quantity', '0.000')
            ->assertJsonPath('data.rejected_quantity', '99.000');

        $this->actingAs($erp['production'], 'sanctum')->postJson("/api/erp/production/orders/{$order}/close")
            ->assertOk()->assertJsonPath('data.variance_value', '299040.00');
        $this->assertSame(0.0, $this->wip($erp));
        $this->assertJournalsBalance($erp);
    }

    public function test_genealogy_traces_a_finished_batch_to_its_materials_and_back(): void
    {
        $erp = $this->factory();
        $order = $this->releasedOrder($erp);
        $this->issueAll($erp, $order);
        $this->qc($erp, $this->receive($erp, $order), 'release')->assertCreated();

        $finished = $this->actingAs($erp['production'], 'sanctum')->getJson('/api/erp/production/genealogy?batch=W500-A1')->assertOk();
        $materials = collect($finished->json('data.as_finished.0.materials'));
        $this->assertEqualsCanonicalizing(['P1', 'P2', null], $materials->pluck('batch_number')->all());
        $this->assertEqualsWithDelta(1000, $materials->firstWhere('batch_number', 'P1')['quantity'], 0.001);
        $this->assertEqualsWithDelta(1448, $materials->firstWhere('batch_number', 'P2')['quantity'], 0.001);

        $material = $this->getJson('/api/erp/production/genealogy?batch=P2')->assertOk();
        $material->assertJsonPath('data.as_material.0.order.id', $order)
            ->assertJsonPath('data.as_material.0.finished_batches.0.batch_number', 'W500-A1');
        $this->assertEqualsWithDelta(1448, $material->json('data.as_material.0.quantity'), 0.001);

        $this->getJson('/api/erp/production/genealogy?batch=NOPE')->assertOk()
            ->assertJsonCount(0, 'data.as_finished')->assertJsonCount(0, 'data.as_material');
    }

    public function test_the_requirement_check_shows_shortfalls_before_an_order_is_planned(): void
    {
        $erp = $this->factory();
        $this->bom($erp);

        $check = $this->actingAs($erp['production'], 'sanctum')->postJson('/api/erp/production/orders/check', [
            'product_id' => $erp['water']->id, 'planned_quantity' => 200, 'materials_warehouse_id' => $erp['main']->id,
        ])->assertOk();

        // 200 cartons need 4,896 preforms (2% allowance) against 3,000 held.
        $this->assertEqualsWithDelta(4896, $check->json('data.requirements.0.required_quantity'), 0.001);
        $this->assertEqualsWithDelta(1896, $check->json('data.requirements.0.shortfall_quantity'), 0.001);
        $this->assertFalse($check->json('data.requirements.0.sufficient'));
        $this->assertTrue($check->json('data.requirements.1.sufficient'));
        $this->assertCount(2, $check->json('data.requirements.0.batches'));
    }

    public function test_a_product_has_one_active_bom_version_and_a_used_version_is_frozen(): void
    {
        $erp = $this->factory();
        $order = $this->releasedOrder($erp);
        $first = ProductionOrder::acrossTenants()->findOrFail($order)->bom_id;

        $this->actingAs($erp['production'], 'sanctum')->putJson("/api/erp/production/boms/{$first}", [
            'output_quantity' => 100, 'lines' => [['product_id' => $erp['label']->id, 'quantity' => 2400]],
        ])->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'new version'));

        $second = $this->postJson("/api/erp/production/boms/{$first}/versions")->assertCreated()
            ->assertJsonPath('data.version', 2)->assertJsonPath('data.is_active', false)->json('data.id');
        $this->postJson("/api/erp/production/boms/{$second}/activate")->assertOk();

        $this->assertSame([$second], Bom::acrossTenants()->where('product_id', $erp['water']->id)->where('is_active', true)->pluck('id')->all());

        // A raw material cannot have a bill of materials.
        $this->postJson('/api/erp/production/boms', [
            'product_id' => $erp['label']->id, 'output_quantity' => 1,
            'lines' => [['product_id' => $erp['preform']->id, 'quantity' => 1]],
        ])->assertStatus(422);
    }

    public function test_each_step_needs_its_own_permission(): void
    {
        $erp = $this->factory();
        $order = $this->releasedOrder($erp);

        $this->actingAs($erp['storekeeper'], 'sanctum')->postJson('/api/erp/production/orders', [])->assertForbidden();
        $this->actingAs($erp['storekeeper'], 'sanctum')->postJson("/api/erp/production/orders/{$order}/close")->assertForbidden();
        $this->actingAs($erp['accountant'], 'sanctum')->postJson("/api/erp/production/orders/{$order}/issue", ['lines' => []])->assertForbidden();
        $this->actingAs($erp['ceo'], 'sanctum')->getJson('/api/erp/production/overview')->assertOk();
        $this->actingAs($erp['ceo'], 'sanctum')->postJson("/api/erp/production/orders/{$order}/release")->assertForbidden();
        $this->actingAs($erp['employee'], 'sanctum')->getJson('/api/erp/production/orders')->assertForbidden();

        $receipt = $this->receive($erp, $order);
        $this->actingAs($erp['storekeeper'], 'sanctum')->postJson("/api/erp/production/receipts/{$receipt}/qc", [
            'decision' => 'release', 'parameters' => [['name' => 'pH', 'passed' => true]],
        ])->assertForbidden();

        // A company that has not switched production on is told so.
        $erp['company']->forceFill(['modules' => ['vouchflow', 'inventory', 'accounting']])->save();
        $this->actingAs($erp['production']->fresh(), 'sanctum')->getJson('/api/erp/production/orders')
            ->assertForbidden()->assertJsonPath('code', 'module_disabled');
    }

    public function test_another_companys_production_records_are_invisible_and_unusable(): void
    {
        $mine = $this->factory('Maji Safi');
        $theirs = $this->factory('Kilimanjaro Springs');
        $order = $this->releasedOrder($theirs);
        $receipt = $this->receive($theirs, $order);
        $bom = ProductionOrder::acrossTenants()->findOrFail($order)->bom_id;

        $this->actingAs($mine['production'], 'sanctum');
        $this->getJson("/api/erp/production/orders/{$order}")->assertNotFound();
        $this->getJson("/api/erp/production/boms/{$bom}")->assertNotFound();
        $this->postJson("/api/erp/production/orders/{$order}/issue", ['lines' => [['product_id' => $theirs['label']->id, 'quantity' => 1]]])->assertNotFound();
        $this->postJson("/api/erp/production/receipts/{$receipt}/qc", ['decision' => 'reject', 'parameters' => [['name' => 'pH', 'passed' => false]]])->assertNotFound();
        $this->getJson('/api/erp/production/orders')->assertOk()->assertJsonCount(0, 'data');

        // Their product cannot go on my bill of materials.
        $this->postJson('/api/erp/production/boms', [
            'product_id' => $mine['water']->id, 'output_quantity' => 1,
            'lines' => [['product_id' => $theirs['label']->id, 'quantity' => 1]],
        ])->assertStatus(422)->assertJsonValidationErrors(['lines.0.product_id']);
    }
}
