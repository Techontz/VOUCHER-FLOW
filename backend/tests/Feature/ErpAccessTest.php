<?php

namespace Tests\Feature;

use App\Models\Erp\Account;
use App\Models\Erp\Product;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Who may do what, and where: setup, modules, permissions, configurable
 * roles, tenant isolation and the double-entry rules. Acceptance criteria 13
 * and 14 of the requirements live here.
 */
class ErpAccessTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    public function test_a_company_that_has_not_set_up_sees_no_erp_modules(): void
    {
        $tenant = $this->makeTenant('Old Tenant');

        $this->actingAs($tenant['admin'], 'sanctum')->getJson('/api/erp/config')
            ->assertOk()
            ->assertJsonPath('data.is_set_up', false)
            ->assertJsonPath('data.modules', ['vouchflow']);

        $this->getJson('/api/erp/products')->assertForbidden()->assertJsonPath('code', 'module_disabled');
    }

    public function test_setup_applies_the_template_and_is_safe_to_run_again(): void
    {
        $tenant = $this->makeTenant('Afya Pharmacy');

        $first = $this->actingAs($tenant['admin'], 'sanctum')
            ->postJson('/api/erp/setup', ['business_type' => 'pharmacy'])
            ->assertOk()
            ->assertJsonPath('data.is_set_up', true)
            ->assertJsonPath('data.settings.product_defaults.track_expiry', true)
            ->assertJsonPath('data.settings.expiry_alert_days', 90)
            ->json('created');

        $this->assertGreaterThan(0, $first['units']);
        $this->assertSame(1, $first['warehouses']);
        $this->assertGreaterThan(20, $first['accounts']);

        $again = $this->postJson('/api/erp/setup', ['business_type' => 'pharmacy'])->assertOk()->json('created');
        $this->assertSame(['units' => 0, 'categories' => 0, 'warehouses' => 0, 'accounts' => 0], $again);

        // A product created afterwards inherits the template's tracking.
        $unit = $this->getJson('/api/erp/units')->json('data.0.id');
        $this->postJson('/api/erp/products', ['sku' => 'AMX-500', 'name' => 'Amoxicillin 500mg', 'unit_id' => $unit])
            ->assertCreated()
            ->assertJsonPath('data.track_batches', true)
            ->assertJsonPath('data.track_expiry', true);
    }

    public function test_only_an_administrator_configures_the_business(): void
    {
        $tenant = $this->makeTenant('Maji Bora');

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson('/api/erp/setup', ['business_type' => 'wholesale'])
            ->assertForbidden();
    }

    public function test_preparing_and_posting_are_separate_permissions(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));

        $id = $this->actingAs($erp['storekeeper'], 'sanctum')->postJson('/api/erp/stock-documents', [
            'type' => 'grn', 'warehouse_id' => $erp['main']->id,
            'lines' => [['product_id' => $erp['product']->id, 'quantity' => 5, 'unit_cost' => 10]],
        ])->assertCreated()->json('data.id');

        $this->postJson("/api/erp/stock-documents/{$id}/post")->assertForbidden();
        $this->actingAs($erp['warehouse_manager'], 'sanctum')->postJson("/api/erp/stock-documents/{$id}/post")->assertOk();
    }

    public function test_people_without_finance_permissions_cannot_read_the_ledger(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));

        foreach (['storekeeper', 'employee', 'hod'] as $who) {
            $this->actingAs($erp[$who], 'sanctum')->getJson('/api/erp/trial-balance')->assertForbidden();
            $this->getJson('/api/erp/journals')->assertForbidden();
        }

        $this->actingAs($erp['accountant'], 'sanctum')->getJson('/api/erp/trial-balance')->assertOk();
    }

    public function test_a_company_can_rescope_a_built_in_role_and_define_its_own(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));

        // Storekeepers here may also post.
        $this->actingAs($erp['admin'], 'sanctum')
            ->putJson('/api/erp/roles/storekeeper', ['permissions' => ['inventory.view', 'inventory.receive', 'inventory.post']])
            ->assertOk();

        $id = $this->actingAs($erp['storekeeper'], 'sanctum')->postJson('/api/erp/stock-documents', [
            'type' => 'grn', 'warehouse_id' => $erp['main']->id,
            'lines' => [['product_id' => $erp['product']->id, 'quantity' => 5, 'unit_cost' => 10]],
        ])->json('data.id');
        $this->postJson("/api/erp/stock-documents/{$id}/post")->assertOk();

        // A role of the company's own, assignable to an employee.
        $key = $this->actingAs($erp['admin'], 'sanctum')
            ->postJson('/api/erp/roles', ['name' => 'Stock Auditor', 'permissions' => ['inventory.view']])
            ->assertCreated()->json('data.key');

        $this->putJson("/api/employees/{$erp['employee']->id}", ['role' => $key])->assertOk();

        $this->actingAs($erp['employee']->fresh(), 'sanctum')->getJson('/api/erp/products')->assertOk();
        $this->postJson('/api/erp/products', ['sku' => 'X', 'name' => 'X', 'unit_id' => $erp['product']->unit_id])->assertForbidden();

        // Its holders keep it until they are moved.
        $this->actingAs($erp['admin'], 'sanctum')->deleteJson("/api/erp/roles/{$key}")->assertStatus(422);
    }

    public function test_the_administrator_role_cannot_be_narrowed(): void
    {
        $tenant = $this->makeTenant('Maji Bora');

        $this->actingAs($tenant['admin'], 'sanctum')
            ->putJson('/api/erp/roles/company_admin', ['permissions' => []])
            ->assertStatus(422);
    }

    public function test_another_companys_erp_records_are_invisible_and_unusable(): void
    {
        $mine = $this->setUpErp($this->makeTenant('Maji Bora'));
        $theirs = $this->setUpErp($this->makeTenant('Zamani Freight'));

        $this->actingAs($mine['admin'], 'sanctum');

        $this->getJson("/api/erp/products/{$theirs['product']->id}")->assertNotFound();
        $this->getJson('/api/erp/products')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $mine['product']->id);

        // Their warehouse and product cannot be used on my document.
        $this->postJson('/api/erp/stock-documents', [
            'type' => 'grn', 'warehouse_id' => $theirs['main']->id,
            'lines' => [['product_id' => $theirs['product']->id, 'quantity' => 1, 'unit_cost' => 1]],
        ])->assertStatus(422)->assertJsonValidationErrors(['warehouse_id', 'lines.0.product_id']);

        $theirAccount = app(TenantContext::class)->forCompany($theirs['company'], fn () => Account::where('code', '1100')->first());
        $mineAccount = app(TenantContext::class)->forCompany($mine['company'], fn () => Account::where('code', '1200')->first());

        $this->postJson('/api/erp/journals', ['memo' => 'Cross-tenant', 'lines' => [
            ['account_id' => $theirAccount->id, 'debit' => 100],
            ['account_id' => $mineAccount->id, 'credit' => 100],
        ]])->assertStatus(422);
    }

    public function test_a_manual_journal_must_balance_and_reverses_cleanly(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        [$cash, $capital] = app(TenantContext::class)->forCompany($erp['company'], fn () => [
            Account::where('system_key', 'cash')->first(), Account::where('system_key', 'share_capital')->first(),
        ]);

        $this->actingAs($erp['accountant'], 'sanctum')->postJson('/api/erp/journals', ['memo' => 'Capital', 'lines' => [
            ['account_id' => $cash->id, 'debit' => 1000],
            ['account_id' => $capital->id, 'credit' => 999.99],
        ]])->assertStatus(422)->assertJsonPath('message', 'Debits (1,000.00) and credits (999.99) must be equal.');

        $id = $this->postJson('/api/erp/journals', ['memo' => 'Capital', 'lines' => [
            ['account_id' => $cash->id, 'debit' => 1000],
            ['account_id' => $capital->id, 'credit' => 1000],
        ]])->assertCreated()->json('data.id');

        // Only finance reverses.
        $this->postJson("/api/erp/journals/{$id}/reverse", ['reason' => 'Duplicate'])->assertForbidden();
        $this->actingAs($erp['finance'], 'sanctum')->postJson("/api/erp/journals/{$id}/reverse", ['reason' => 'Duplicate'])->assertOk();
        $this->postJson("/api/erp/journals/{$id}/reverse", ['reason' => 'Again'])->assertStatus(422);

        $tb = $this->getJson('/api/erp/trial-balance')->json('data');
        $this->assertTrue($tb['balanced']);
        $this->assertEquals(0, collect($tb['rows'])->firstWhere('code', '1100')['balance']);
    }

    public function test_a_product_with_history_is_deactivated_rather_than_deleted(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));

        $id = $this->actingAs($erp['storekeeper'], 'sanctum')->postJson('/api/erp/stock-documents', [
            'type' => 'opening', 'warehouse_id' => $erp['main']->id,
            'lines' => [['product_id' => $erp['product']->id, 'quantity' => 5, 'unit_cost' => 10]],
        ])->json('data.id');
        $this->actingAs($erp['warehouse_manager'], 'sanctum')->postJson("/api/erp/stock-documents/{$id}/post")->assertOk();

        $this->deleteJson("/api/erp/products/{$erp['product']->id}")->assertOk();

        $this->assertFalse(app(TenantContext::class)->forCompany($erp['company'], fn () => Product::find($erp['product']->id))->is_active);
    }

    public function test_erp_roles_see_only_their_own_vouchers(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));
        $this->makeVoucher($erp);

        $this->actingAs($erp['storekeeper'], 'sanctum')->getJson('/api/vouchers')->assertOk()->assertJsonCount(0, 'data');
        $this->assertSame('Storekeeper', User::roleLabel('storekeeper'));
    }
}
