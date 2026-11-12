<?php

namespace Tests\Feature;

use App\Models\Erp\Finance\AssetDepreciationLine;
use App\Models\Erp\JournalEntry;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Fixed assets: capitalisation posts once, depreciation posts once per asset
 * per month and adds up to the schedule, and a disposal posts the right gain
 * or loss.
 */
class ErpFinanceAssetsTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    /** @return array<string, mixed> */
    private function assets(string $name = 'Maji Bora'): array
    {
        $erp = $this->setUpErp($this->makeTenant($name));
        $erp['company']->update(['modules' => [...$erp['company']->modules, 'assets']]);
        $erp['company'] = $erp['company']->fresh();

        $erp['bank'] = $this->actingAs($erp['finance'], 'sanctum')->postJson('/api/erp/finance/bank-accounts', [
            'name' => 'NMB Bank', 'type' => 'bank', 'opening_balance' => 500_000_000, 'opening_date' => now()->subYears(2)->startOfYear()->toDateString(),
        ])->assertCreated()->json('data');
        $erp['classes'] = collect($this->getJson('/api/erp/assets/classes')->assertOk()->json('data'))->keyBy('code');

        return $erp;
    }

    private function register(array $erp, array $data): array
    {
        return $this->actingAs($erp['finance'], 'sanctum')->postJson('/api/erp/assets/register', [
            'name' => 'Asset', 'location' => 'Mbezi factory', ...$data,
        ])->assertCreated()->json('data');
    }

    private function tbBalance(array $erp, string $code, ?string $to = null): float
    {
        $tb = $this->actingAs($erp['finance'], 'sanctum')->getJson('/api/erp/trial-balance'.($to ? "?to={$to}" : ''))->json('data');
        $this->assertTrue($tb['balanced']);

        return (float) (collect($tb['rows'])->firstWhere('code', $code)['balance'] ?? 0);
    }

    public function test_the_default_classes_follow_tanzanian_wear_and_tear_rates(): void
    {
        $erp = $this->assets();

        $this->assertEquals(37.5, $erp['classes']['COMP']['rate']);
        $this->assertSame('reducing_balance', $erp['classes']['COMP']['method']);
        $this->assertEquals(25, $erp['classes']['VEH']['rate']);
        $this->assertEquals(12.5, $erp['classes']['FURN']['rate']);
        $this->assertSame('straight_line', $erp['classes']['BLDG']['method']);
        $this->assertSame('1540', $erp['classes']['COMP']['asset_account']['code']);
    }

    public function test_capitalising_posts_the_acquisition_once(): void
    {
        $erp = $this->assets();
        $asset = $this->register($erp, ['name' => 'Bottling line', 'asset_class_id' => $erp['classes']['PLANT']['id'], 'acquisition_date' => now()->subMonths(2)->toDateString(), 'cost' => 120_000_000]);
        $this->assertSame('draft', $asset['status']);
        $this->assertStringStartsWith('FA-', $asset['tag']);
        $this->assertEquals(0, $this->tbBalance($erp, '1520'));

        $this->postJson("/api/erp/assets/register/{$asset['id']}/capitalise", ['funding' => 'bank', 'bank_account_id' => $erp['bank']['id']])->assertOk()->assertJsonPath('data.status', 'active');
        $this->postJson("/api/erp/assets/register/{$asset['id']}/capitalise", ['funding' => 'bank', 'bank_account_id' => $erp['bank']['id']])->assertStatus(422);

        $this->assertEquals(120_000_000, $this->tbBalance($erp, '1520'));
        $this->assertEquals(380_000_000, $this->tbBalance($erp, '1210'));

        // On credit needs the supplier; the cost is fixed once on the books.
        $other = $this->register($erp, ['name' => 'Generator', 'asset_class_id' => $erp['classes']['PLANT']['id'], 'acquisition_date' => now()->toDateString(), 'cost' => 1000]);
        $this->postJson("/api/erp/assets/register/{$other['id']}/capitalise", ['funding' => 'payable'])->assertStatus(422);
        $this->putJson("/api/erp/assets/register/{$asset['id']}", ['name' => 'Bottling line 2', 'cost' => 1])->assertOk()->assertJsonPath('data.cost', '120000000.00');
        $this->deleteJson("/api/erp/assets/register/{$asset['id']}")->assertStatus(422);
        $this->deleteJson("/api/erp/assets/register/{$other['id']}")->assertOk();
    }

    public function test_depreciation_posts_once_per_asset_per_month_and_matches_the_schedule(): void
    {
        $erp = $this->assets();
        $start = now()->subMonths(5)->startOfMonth();

        // Straight line: (3,600,000 - 600,000) / 36 = 83,333.33 a month.
        $computer = $this->register($erp, ['name' => 'Server', 'asset_class_id' => $erp['classes']['COMP']['id'], 'acquisition_date' => $start->toDateString(),
            'cost' => 3_600_000, 'residual_value' => 600_000, 'method' => 'straight_line', 'useful_life_months' => 36]);
        // Reducing balance at 25% a year: 2.0833% of the opening value a month.
        $truck = $this->register($erp, ['name' => 'Isuzu FVZ', 'asset_class_id' => $erp['classes']['VEH']['id'], 'acquisition_date' => $start->toDateString(), 'cost' => 180_000_000]);

        foreach ([$computer, $truck] as $a) {
            $this->postJson("/api/erp/assets/register/{$a['id']}/capitalise", ['funding' => 'bank', 'bank_account_id' => $erp['bank']['id']])->assertOk();
        }

        $first = $start->copy()->addMonth()->format('Y-m');
        $preview = $this->getJson("/api/erp/assets/depreciation-preview?period={$first}")->assertOk()->json('data');
        $this->assertCount(2, $preview['lines']);
        $this->assertEquals(83_333.33 + 3_750_000, $preview['total']);

        $this->postJson('/api/erp/assets/depreciation', ['period' => $first])->assertCreated();
        $this->postJson('/api/erp/assets/depreciation', ['period' => $first])->assertStatus(422);

        // Skip a month: the next run catches up both months, still one line per asset per month.
        $third = $start->copy()->addMonths(3)->format('Y-m');
        $this->postJson('/api/erp/assets/depreciation', ['period' => $third])->assertCreated()->assertJsonPath('data.assets_count', 2)->assertJsonCount(4, 'data.lines');
        // An earlier month cannot be run after a later one; the future cannot be run.
        $this->postJson('/api/erp/assets/depreciation', ['period' => $start->copy()->addMonths(2)->format('Y-m')])->assertStatus(422);
        $this->postJson('/api/erp/assets/depreciation', ['period' => now()->addMonth()->format('Y-m')])->assertStatus(422);

        $lines = app(TenantContext::class)->forCompany($erp['company'], fn () => AssetDepreciationLine::query()->get());
        $this->assertCount(6, $lines);
        $this->assertSame($lines->count(), $lines->unique(fn ($l) => $l->fixed_asset_id.$l->period)->count());

        foreach ([$computer, $truck] as $a) {
            $show = $this->getJson("/api/erp/assets/register/{$a['id']}")->assertOk()->json('data');
            $scheduled = collect($show['schedule'])->where('posted', true)->sum('amount');
            $this->assertEqualsWithDelta($scheduled, (float) $show['accumulated_depreciation'], 0.001);
            $this->assertEqualsWithDelta($scheduled, collect($show['depreciation'])->sum(fn ($l) => (float) $l['amount']), 0.001);
        }

        // Straight line ends exactly at the residual value.
        $schedule = $this->getJson("/api/erp/assets/register/{$computer['id']}")->json('data.schedule');
        $this->assertCount(36, $schedule);
        $this->assertEqualsWithDelta(3_000_000, collect($schedule)->sum('amount'), 0.001);
        $this->assertEquals(600_000, end($schedule)['closing']);

        // Reducing balance: month two is 25%/12 of month one's closing value.
        $truckSchedule = $this->getJson("/api/erp/assets/register/{$truck['id']}")->json('data.schedule');
        $this->assertEquals(3_750_000, $truckSchedule[0]['amount']);
        $this->assertEquals(round(176_250_000 * 0.25 / 12, 2), $truckSchedule[1]['amount']);

        // The ledger agrees with the register.
        $posted = round($lines->sum(fn ($l) => (float) $l->amount), 2);
        $this->assertEquals($posted, $this->tbBalance($erp, '6600'));
        $this->assertEquals(-round($lines->where('fixed_asset_id', $truck['id'])->sum(fn ($l) => (float) $l->amount), 2), $this->tbBalance($erp, '1535'));
        $this->assertSame(2, app(TenantContext::class)->forCompany($erp['company'], fn () => JournalEntry::where('source_type', 'AssetDepreciationRun')->count()));
    }

    public function test_a_disposal_posts_the_gain_or_loss_once(): void
    {
        $erp = $this->assets();
        $start = CarbonImmutable::now()->subMonths(4)->startOfMonth();
        $make = function (string $name, float $proceeds) use ($erp, $start) {
            $a = $this->register($erp, ['name' => $name, 'asset_class_id' => $erp['classes']['FURN']['id'], 'acquisition_date' => $start->toDateString(),
                'cost' => 1_200_000, 'method' => 'straight_line', 'useful_life_months' => 12]);
            $this->postJson("/api/erp/assets/register/{$a['id']}/capitalise", ['funding' => 'opening_equity'])->assertOk();

            return $a;
        };
        $desk = $make('Director desk', 1_000_000);
        $chairs = $make('Boardroom chairs', 0);

        // Disposing before the depreciation due is posted is refused.
        $this->postJson("/api/erp/assets/register/{$desk['id']}/dispose", ['disposal_date' => now()->toDateString(), 'proceeds' => 1, 'bank_account_id' => $erp['bank']['id'], 'reason' => 'Sold'])->assertStatus(422);

        // Three months at 100,000: book value 900,000.
        $this->postJson('/api/erp/assets/depreciation', ['period' => now()->subMonth()->format('Y-m')])->assertCreated();

        // Sold for 1,000,000: gain 100,000.
        $this->postJson("/api/erp/assets/register/{$desk['id']}/dispose", ['disposal_date' => now()->toDateString(), 'proceeds' => 1_000_000, 'reason' => 'Sold'])->assertStatus(422);
        $this->postJson("/api/erp/assets/register/{$desk['id']}/dispose", ['disposal_date' => now()->toDateString(), 'proceeds' => 1_000_000, 'bank_account_id' => $erp['bank']['id'], 'reason' => 'Sold to staff'])
            ->assertOk()->assertJsonPath('data.status', 'disposed')->assertJsonPath('data.disposal_gain_loss', '100000.00');
        $this->postJson("/api/erp/assets/register/{$desk['id']}/dispose", ['disposal_date' => now()->toDateString(), 'proceeds' => 1, 'bank_account_id' => $erp['bank']['id'], 'reason' => 'Again'])->assertStatus(422);

        // Scrapped for nothing: loss of the whole book value.
        $this->postJson("/api/erp/assets/register/{$chairs['id']}/dispose", ['disposal_date' => now()->toDateString(), 'reason' => 'Broken'])
            ->assertOk()->assertJsonPath('data.disposal_gain_loss', '-900000.00');

        $this->assertEquals(0, $this->tbBalance($erp, '1550'));
        $this->assertEquals(0, $this->tbBalance($erp, '1555'));
        $this->assertEquals(100_000, $this->tbBalance($erp, '4900'));
        $this->assertEquals(900_000, $this->tbBalance($erp, '6620'));

        // A disposed asset depreciates no more.
        $this->getJson('/api/erp/assets/depreciation-preview?period='.now()->format('Y-m'))->assertOk()->assertJsonCount(0, 'data.lines');
        $history = collect($this->getJson("/api/erp/assets/register/{$desk['id']}")->json('data.events'))->pluck('type')->all();
        $this->assertSame(['registered', 'capitalised', 'disposed'], $history);
    }

    public function test_transfers_are_recorded_in_the_asset_history(): void
    {
        $erp = $this->assets();
        $asset = $this->register($erp, ['name' => 'Generator 250kVA', 'asset_class_id' => $erp['classes']['PLANT']['id'], 'acquisition_date' => now()->toDateString(), 'cost' => 85_000_000, 'custodian_user_id' => $erp['storekeeper']->id]);

        $this->postJson("/api/erp/assets/register/{$asset['id']}/transfer", ['location' => 'Arusha depot', 'custodian_user_id' => $erp['warehouse_manager']->id, 'notes' => 'Depot backup power'])->assertOk()
            ->assertJsonPath('data.location', 'Arusha depot');
        $this->postJson("/api/erp/assets/register/{$asset['id']}/transfer", ['location' => 'Arusha depot', 'custodian_user_id' => $erp['warehouse_manager']->id])->assertStatus(422);

        $event = collect($this->getJson("/api/erp/assets/register/{$asset['id']}")->json('data.events'))->firstWhere('type', 'transferred');
        $this->assertSame('Mbezi factory', $event['from_location']);
        $this->assertSame($erp['storekeeper']->id, $event['from_custodian_id']);
    }

    public function test_asset_permissions_and_tenant_isolation(): void
    {
        $erp = $this->assets('Maji Bora');
        $theirs = $this->assets('Zamani Freight');
        $theirAsset = $this->register($theirs, ['name' => 'Their truck', 'asset_class_id' => $theirs['classes']['VEH']['id'], 'acquisition_date' => now()->toDateString(), 'cost' => 1000]);

        $this->actingAs($erp['finance'], 'sanctum')->getJson("/api/erp/assets/register/{$theirAsset['id']}")->assertNotFound();
        $this->postJson("/api/erp/assets/register/{$theirAsset['id']}/capitalise", ['funding' => 'opening_equity'])->assertNotFound();
        $this->postJson('/api/erp/assets/register', ['name' => 'X', 'asset_class_id' => $theirs['classes']['VEH']['id'], 'acquisition_date' => now()->toDateString(), 'cost' => 10])
            ->assertStatus(422)->assertJsonValidationErrors('asset_class_id');
        $this->getJson('/api/erp/assets/register')->assertOk()->assertJsonCount(0, 'data');

        // The accountant depreciates but does not register or dispose; the CEO only looks.
        $mine = $this->register($erp, ['name' => 'Laptop', 'asset_class_id' => $erp['classes']['COMP']['id'], 'acquisition_date' => now()->toDateString(), 'cost' => 2_500_000]);
        $this->actingAs($erp['accountant'], 'sanctum')->getJson('/api/erp/assets/depreciation-preview?period='.now()->format('Y-m'))->assertOk();
        $this->postJson('/api/erp/assets/register', [])->assertForbidden();
        $this->postJson("/api/erp/assets/register/{$mine['id']}/dispose", ['disposal_date' => now()->toDateString(), 'reason' => 'x x x'])->assertForbidden();
        $this->actingAs($erp['ceo'], 'sanctum')->getJson('/api/erp/assets/overview')->assertOk();
        $this->postJson('/api/erp/assets/depreciation', ['period' => now()->format('Y-m')])->assertForbidden();
        $this->actingAs($erp['storekeeper'], 'sanctum')->getJson('/api/erp/assets/register')->assertForbidden();

        // A company without the module is told so.
        $erp['company']->update(['modules' => ['vouchflow', 'inventory', 'accounting']]);
        $this->actingAs($erp['finance']->fresh(), 'sanctum')->getJson('/api/erp/assets/register')->assertForbidden()->assertJsonPath('code', 'module_disabled');
    }
}
