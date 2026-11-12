<?php

namespace Tests\Feature;

use App\Models\Erp\Account;
use App\Models\Erp\Customer;
use App\Models\Erp\Fleet\FleetCostAllocation;
use App\Models\Erp\Fleet\FleetDriver;
use App\Models\Erp\Fleet\FleetFuelStandard;
use App\Models\Erp\Fleet\FleetMaintenanceSchedule;
use App\Models\Erp\Fleet\FleetTrip;
use App\Models\Erp\Fleet\FleetVehicle;
use App\Models\Erp\JournalEntry;
use App\Models\Erp\Supplier;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Fleet & transport. Acceptance criteria 7 (transport costs are recorded on
 * trips under the four options and post correctly) and 8 (hired vehicles are
 * not double-counted) live here, with the fuel standard, exactly-once posting,
 * fixed-cost allocation, drivers' own-trip boundary and tenant isolation.
 */
class ErpFleetTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    /** A transport company with an owned truck, a wet-hired and a dry-hired truck, drivers and a customer. */
    private function fleet(string $name = 'Safari Freight'): array
    {
        $erp = $this->setUpErp($this->makeTenant($name), 'transport');
        $company = $erp['company'];

        return app(TenantContext::class)->forCompany($company, function () use ($erp, $company) {
            $slug = $company->slug;
            $make = fn (string $key, string $role) => User::create([
                'company_id' => $company->id, 'name' => ucfirst($key)." {$slug}", 'email' => "{$key}@{$slug}.test",
                'password' => 'Password123!', 'role' => $role, 'status' => 'active',
            ]);

            $owner = Supplier::create(['company_id' => $company->id, 'code' => 'OWN-1', 'name' => 'Mzee Transporters']);
            $truck = FleetVehicle::create([
                'company_id' => $company->id, 'registration_number' => 'T 123 ABC', 'make' => 'Isuzu', 'model' => 'FVZ',
                'type' => 'truck', 'ownership' => 'owned', 'odometer' => 10000,
                'monthly_insurance' => 600000, 'monthly_licence' => 150000, 'monthly_depreciation' => 2250000,
                'allocation_basis' => 'days',
            ]);
            $wet = FleetVehicle::create([
                'company_id' => $company->id, 'registration_number' => 'T 777 HRD', 'type' => 'truck', 'ownership' => 'hired',
                'supplier_id' => $owner->id, 'hire_rate_basis' => 'per_km', 'hire_rate' => 1500, 'hire_includes_fuel' => true,
            ]);
            $dry = FleetVehicle::create([
                'company_id' => $company->id, 'registration_number' => 'T 888 HRD', 'type' => 'truck', 'ownership' => 'hired',
                'supplier_id' => $owner->id, 'hire_rate_basis' => 'per_trip', 'hire_rate' => 400000, 'hire_includes_fuel' => false,
            ]);

            $driverUser = $make('driver', User::ROLE_DRIVER);
            $otherDriverUser = $make('driver2', User::ROLE_DRIVER);

            return [
                ...$erp,
                'owner' => $owner, 'truck' => $truck, 'wet' => $wet, 'dry' => $dry,
                'fleet_manager' => $make('fleetmgr', User::ROLE_FLEET_MANAGER),
                'dispatcher' => $make('dispatch', User::ROLE_DISPATCH),
                'driver_user' => $driverUser,
                'other_driver_user' => $otherDriverUser,
                'driver' => FleetDriver::create(['company_id' => $company->id, 'user_id' => $driverUser->id, 'licence_number' => 'DL-001', 'licence_class' => 'E', 'licence_expiry' => now()->addYear(), 'daily_allowance' => 25000]),
                'other_driver' => FleetDriver::create(['company_id' => $company->id, 'user_id' => $otherDriverUser->id, 'licence_number' => 'DL-002', 'licence_expiry' => now()->addYear(), 'daily_allowance' => 25000]),
                'customer' => Customer::create(['company_id' => $company->id, 'code' => 'CUS-1', 'name' => 'Mwanza Wholesalers']),
                'cash' => Account::where('system_key', 'cash')->first(),
                'standard' => FleetFuelStandard::create(['company_id' => $company->id, 'vehicle_id' => $truck->id, 'basis' => 'per_100km', 'litres' => 35, 'tolerance_percent' => 10]),
            ];
        });
    }

    private function plan(array $f, array $data, string $as = 'dispatcher'): TestResponse
    {
        return $this->actingAs($f[$as], 'sanctum')->postJson('/api/erp/fleet/trips', [
            'origin' => 'Dar es Salaam', 'destination' => 'Morogoro', 'distance_km' => 200,
            'planned_start' => now()->subDays(2)->toDateTimeString(),
            ...$data,
        ]);
    }

    /** Plans, dispatches and completes a trip; returns its id. */
    private function runTrip(array $f, array $data, float $out, ?float $in, array $fuel = [], array $expenses = []): int
    {
        $id = $this->plan($f, $data)->assertCreated()->json('data.id');
        $this->actingAs($f['dispatcher'], 'sanctum')->postJson("/api/erp/fleet/trips/{$id}/dispatch", [
            'odometer_out' => $out, 'at' => now()->subDays(2)->toDateTimeString(),
        ])->assertOk();

        foreach ($fuel as $litres) {
            $this->actingAs($f['fleet_manager'], 'sanctum')->postJson("/api/erp/fleet/trips/{$id}/fuel", [
                'litres' => $litres, 'price_per_litre' => 3000, 'station' => 'Puma Ubungo', 'account_id' => $f['cash']->id,
            ])->assertCreated()->assertJsonPath('data.status', 'approved');
        }

        foreach ($expenses as $expense) {
            $this->actingAs($f['fleet_manager'], 'sanctum')->postJson("/api/erp/fleet/trips/{$id}/expenses", [
                'account_id' => $f['cash']->id, ...$expense,
            ])->assertCreated();
        }

        $this->actingAs($f['dispatcher'], 'sanctum')->postJson("/api/erp/fleet/trips/{$id}/complete", [
            'odometer_in' => $in, 'at' => now()->subDay()->toDateTimeString(),
        ])->assertOk()->assertJsonPath('data.status', 'completed');

        return $id;
    }

    /** @return array<string, array{debit: float, credit: float}> by system key (or code) */
    private function lines(array $f, int $tripId, string $purpose): array
    {
        return app(TenantContext::class)->forCompany($f['company'], function () use ($tripId, $purpose) {
            $entry = JournalEntry::query()->with('lines.account')->where('source_type', 'FleetTrip')
                ->where('source_id', $tripId)->where('purpose', $purpose)->first();

            if (! $entry) {
                return [];
            }

            $out = [];
            foreach ($entry->lines as $line) {
                $key = $line->account->system_key ?? $line->account->code;
                $out[$key]['debit'] = ($out[$key]['debit'] ?? 0) + (float) $line->debit;
                $out[$key]['credit'] = ($out[$key]['credit'] ?? 0) + (float) $line->credit;
            }

            $this->assertEqualsWithDelta((float) $entry->lines->sum('debit'), (float) $entry->lines->sum('credit'), 0.001, 'Every fleet journal balances.');

            return $out;
        });
    }

    private function journalCount(int $tripId): int
    {
        return JournalEntry::acrossTenants()->where('source_type', 'FleetTrip')->where('source_id', $tripId)->count();
    }

    public function test_a_company_vehicle_charged_to_the_customer_posts_its_costs_and_its_revenue_once(): void
    {
        $f = $this->fleet();

        $id = $this->runTrip($f, [
            'cost_option' => 'charged', 'vehicle_id' => $f['truck']->id, 'driver_id' => $f['driver']->id,
            'customer_id' => $f['customer']->id, 'transport_charge' => 900000,
            'source_type' => 'loading_order', 'source_id' => 12, 'source_reference' => 'LO-2026-000012',
        ], 10000, 10200, [70], [
            ['type' => 'toll', 'rate' => 20000],
            ['type' => 'allowance', 'quantity' => 2], // the driver's daily rate applies
        ]);

        $this->actingAs($f['dispatcher'], 'sanctum')->postJson("/api/erp/fleet/trips/{$id}/close")
            ->assertOk()->assertJsonPath('data.status', 'closed')
            ->assertJsonPath('data.source_reference', 'LO-2026-000012')
            ->assertJsonPath('data.costs.revenue', 900000)
            ->assertJsonPath('data.costs.fuel', 210000)
            ->assertJsonPath('data.costs.expenses', 70000);

        $costs = $this->lines($f, $id, 'close');
        $this->assertSame(210000.0, $costs['fuel']['debit']);
        $this->assertSame(20000.0, $costs['fleet_tolls']['debit']);
        $this->assertSame(50000.0, $costs['fleet_allowances']['debit']);
        $this->assertSame(280000.0, $costs['cash']['credit']);

        $charge = $this->lines($f, $id, 'charge');
        $this->assertSame(900000.0, $charge['receivable']['debit']);
        $this->assertSame(900000.0, $charge['transport_revenue']['credit']);

        // Exactly once: a second close is refused and nothing more is posted.
        $this->actingAs($f['fleet_manager'], 'sanctum')->postJson("/api/erp/fleet/trips/{$id}/close")->assertStatus(422);
        $this->assertSame(2, $this->journalCount($id));

        // And nothing more can be charged to a closed trip.
        $this->actingAs($f['fleet_manager'], 'sanctum')->postJson("/api/erp/fleet/trips/{$id}/fuel", [
            'litres' => 10, 'price_per_litre' => 3000, 'account_id' => $f['cash']->id,
        ])->assertStatus(422);

        // The vehicle came back available with the odometer it returned on.
        $truck = FleetVehicle::acrossTenants()->find($f['truck']->id);
        $this->assertSame('available', $truck->status);
        $this->assertSame(10200.0, (float) $truck->odometer);
    }

    public function test_transport_included_in_the_price_carries_cost_only_and_a_customers_own_vehicle_carries_nothing(): void
    {
        $f = $this->fleet();

        $included = $this->runTrip($f, [
            'cost_option' => 'included', 'vehicle_id' => $f['truck']->id, 'driver_id' => $f['driver']->id,
            'customer_id' => $f['customer']->id, 'transport_charge' => 500000,
        ], 10000, 10200, [60]);

        $this->assertSame(0.0, (float) FleetTrip::acrossTenants()->find($included)->transport_charge, 'Included transport records no charge.');
        $this->actingAs($f['dispatcher'], 'sanctum')->postJson("/api/erp/fleet/trips/{$included}/close")
            ->assertOk()->assertJsonPath('data.costs.revenue', 0);
        $this->assertSame(180000.0, $this->lines($f, $included, 'close')['fuel']['debit']);
        $this->assertSame([], $this->lines($f, $included, 'charge'));

        $collect = $this->plan($f, ['cost_option' => 'customer_vehicle', 'customer_id' => $f['customer']->id, 'external_vehicle' => 'T 456 XYZ'])
            ->assertCreated()->json('data.id');

        $this->actingAs($f['fleet_manager'], 'sanctum')->postJson("/api/erp/fleet/trips/{$collect}/fuel", [
            'litres' => 10, 'price_per_litre' => 3000, 'account_id' => $f['cash']->id,
        ])->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, "customer's own vehicle"));

        $this->actingAs($f['dispatcher'], 'sanctum');
        $this->postJson("/api/erp/fleet/trips/{$collect}/dispatch")->assertOk();
        $this->postJson("/api/erp/fleet/trips/{$collect}/complete")->assertOk();
        $this->postJson("/api/erp/fleet/trips/{$collect}/close")->assertOk()->assertJsonPath('data.costs.total_cost', 0);
        $this->assertSame(0, $this->journalCount($collect));

        // A company vehicle cannot be put on the customer's own vehicle option.
        $this->plan($f, ['cost_option' => 'customer_vehicle', 'customer_id' => $f['customer']->id, 'vehicle_id' => $f['truck']->id])
            ->assertStatus(422);
        // A charged trip needs a charge.
        $this->plan($f, ['cost_option' => 'charged', 'vehicle_id' => $f['truck']->id, 'driver_id' => $f['driver']->id, 'customer_id' => $f['customer']->id])
            ->assertStatus(422);
    }

    public function test_a_hired_vehicle_carries_its_hire_once_and_nothing_its_owner_already_pays_for(): void
    {
        $f = $this->fleet();

        // A hired truck must go under the hired option, and an owned one cannot.
        $this->plan($f, ['cost_option' => 'included', 'vehicle_id' => $f['wet']->id, 'driver_id' => $f['driver']->id])->assertStatus(422);
        $this->plan($f, ['cost_option' => 'hired', 'vehicle_id' => $f['truck']->id])->assertStatus(422);

        $id = $this->plan($f, [
            'cost_option' => 'hired', 'vehicle_id' => $f['wet']->id, 'customer_id' => $f['customer']->id,
            'transport_charge' => 800000, 'destination' => 'Dodoma', 'distance_km' => 450,
        ])->assertCreated()->json('data.id');
        $this->actingAs($f['dispatcher'], 'sanctum')->postJson("/api/erp/fleet/trips/{$id}/dispatch", ['odometer_out' => 50000])->assertOk();

        // Wet hire: the owner pays the fuel, so the company cannot pay it too.
        $this->actingAs($f['fleet_manager'], 'sanctum')->postJson("/api/erp/fleet/trips/{$id}/fuel", [
            'litres' => 100, 'price_per_litre' => 3000, 'account_id' => $f['cash']->id,
        ])->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'owner pays for fuel'));

        $this->actingAs($f['dispatcher'], 'sanctum')->postJson("/api/erp/fleet/trips/{$id}/complete", ['odometer_in' => 50400])
            ->assertOk()->assertJsonPath('data.hire_cost', '600000.00');
        $this->postJson("/api/erp/fleet/trips/{$id}/close")->assertOk()
            ->assertJsonPath('data.costs.hire', 600000)
            ->assertJsonPath('data.costs.fuel', 0)
            ->assertJsonPath('data.costs.fixed', 0)
            ->assertJsonPath('data.costs.profit', 200000);

        $costs = $this->lines($f, $id, 'close');
        $this->assertSame(['fleet_vehicle_hire', 'payable'], array_keys($costs), 'The hire is the whole cost: no fuel line beside it.');
        $this->assertSame(600000.0, $costs['fleet_vehicle_hire']['debit']);
        $this->assertSame(600000.0, $costs['payable']['credit']);
        $this->assertSame(0, FleetCostAllocation::acrossTenants()->where('trip_id', $id)->count(), 'A hired truck absorbs none of the fleet\'s fixed costs.');
        $this->assertSame(800000.0, $this->lines($f, $id, 'charge')['transport_revenue']['credit']);

        // The report agrees with the books: the hire appears once.
        $report = $this->actingAs($f['fleet_manager'], 'sanctum')->getJson('/api/erp/fleet/reports/profitability')->assertOk();
        $row = collect($report->json('data.trips'))->firstWhere('id', $id);
        $this->assertSame(600000.0, (float) $row['hire']);
        $this->assertSame(600000.0, (float) $row['total_cost']);

        // A dry hire may take company fuel, and still posts its hire once.
        $dry = $this->runTrip($f, ['cost_option' => 'hired', 'vehicle_id' => $f['dry']->id], 0, 200, [50]);
        $this->actingAs($f['dispatcher'], 'sanctum')->postJson("/api/erp/fleet/trips/{$dry}/close")->assertOk();
        $dryCosts = $this->lines($f, $dry, 'close');
        $this->assertSame(400000.0, $dryCosts['fleet_vehicle_hire']['debit']);
        $this->assertSame(150000.0, $dryCosts['fuel']['debit']);
        $this->assertSame(1, JournalEntry::acrossTenants()->where('source_type', 'FleetTrip')->where('source_id', $dry)->count());
    }

    public function test_a_trip_over_the_fuel_standard_is_flagged_and_only_an_approver_may_close_it(): void
    {
        $f = $this->fleet();
        $trip = ['cost_option' => 'included', 'vehicle_id' => $f['truck']->id, 'driver_id' => $f['driver']->id];

        // 400 km at 35 L/100 km allows 140 L; 10% tolerance takes it to 154 L.
        $over = $this->runTrip($f, $trip, 10000, 10400, [100, 80]);
        $this->actingAs($f['dispatcher'], 'sanctum')->getJson("/api/erp/fleet/trips/{$over}")
            ->assertJsonPath('data.fuel_over_standard', true)
            ->assertJsonPath('data.standard_litres', '140.000')
            ->assertJsonPath('data.fuel_variance_percent', '28.57');

        $this->getJson('/api/erp/fleet/overview')->assertOk()->assertJsonPath('data.fuel_alerts.0.id', $over);

        $this->postJson("/api/erp/fleet/trips/{$over}/close")->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'over the 10% tolerance'));
        $this->assertSame('completed', FleetTrip::acrossTenants()->find($over)->status);
        $this->assertSame(0, $this->journalCount($over));

        $this->actingAs($f['finance'], 'sanctum')->postJson("/api/erp/fleet/trips/{$over}/close")->assertForbidden();
        $this->actingAs($f['fleet_manager'], 'sanctum')->postJson("/api/erp/fleet/trips/{$over}/close", ['note' => 'Detour via Chalinze after a bridge closure'])
            ->assertOk()->assertJsonPath('data.variance_approved_by', $f['fleet_manager']->id);

        // Within tolerance, the dispatcher closes it without anyone else.
        $within = $this->runTrip($f, $trip, 10400, 10800, [150]);
        $this->actingAs($f['dispatcher'], 'sanctum')->postJson("/api/erp/fleet/trips/{$within}/close")
            ->assertOk()->assertJsonPath('data.fuel_over_standard', false);
    }

    public function test_drivers_see_only_their_own_trips_and_what_they_record_waits_for_approval(): void
    {
        $f = $this->fleet();
        $base = ['cost_option' => 'included', 'vehicle_id' => $f['truck']->id];
        $mine = $this->plan($f, [...$base, 'driver_id' => $f['driver']->id])->json('data.id');
        $theirs = $this->plan($f, [...$base, 'driver_id' => $f['other_driver']->id])->json('data.id');
        $this->actingAs($f['dispatcher'], 'sanctum')->postJson("/api/erp/fleet/trips/{$mine}/dispatch", ['odometer_out' => 10000])->assertOk();

        $this->actingAs($f['driver_user'], 'sanctum');
        $this->getJson('/api/erp/fleet/trips')->assertForbidden();
        $this->getJson("/api/erp/fleet/trips/{$mine}")->assertForbidden();
        $this->postJson("/api/erp/fleet/trips/{$mine}/fuel", ['litres' => 10, 'price_per_litre' => 3000, 'account_id' => $f['cash']->id])->assertForbidden();

        $this->getJson('/api/erp/fleet/my-trips')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $mine);
        $this->getJson("/api/erp/fleet/my-trips/{$mine}")->assertOk();
        $this->getJson("/api/erp/fleet/my-trips/{$theirs}")->assertNotFound();
        $this->postJson("/api/erp/fleet/my-trips/{$theirs}/fuel", ['litres' => 10, 'price_per_litre' => 3000, 'account_id' => $f['cash']->id])->assertNotFound();

        $fuel = $this->postJson("/api/erp/fleet/my-trips/{$mine}/fuel", [
            'litres' => 60, 'price_per_litre' => 3100, 'station' => 'Lake Oil Chalinze', 'receipt_number' => 'R-889', 'account_id' => $f['cash']->id,
        ])->assertCreated()->assertJsonPath('data.status', 'pending')->json('data.id');
        $this->postJson("/api/erp/fleet/my-trips/{$mine}/expenses", ['type' => 'parking', 'rate' => 5000, 'account_id' => $f['cash']->id])
            ->assertCreated()->assertJsonPath('data.status', 'pending');

        $this->actingAs($f['dispatcher'], 'sanctum')->postJson("/api/erp/fleet/trips/{$mine}/complete", ['odometer_in' => 10200])->assertOk();
        $this->postJson("/api/erp/fleet/trips/{$mine}/close")->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'waiting for approval'));
        $this->postJson("/api/erp/fleet/fuel/{$fuel}/decision", ['decision' => 'approve'])->assertForbidden();

        $this->actingAs($f['finance'], 'sanctum');
        $pending = $this->getJson('/api/erp/fleet/pending')->assertOk();
        $this->postJson("/api/erp/fleet/fuel/{$fuel}/decision", ['decision' => 'approve'])->assertOk();
        $this->postJson('/api/erp/fleet/expenses/'.$pending->json('data.expenses.0.id').'/decision', ['decision' => 'reject'])->assertStatus(422);
        $this->postJson('/api/erp/fleet/expenses/'.$pending->json('data.expenses.0.id').'/decision', ['decision' => 'reject', 'reason' => 'No receipt'])->assertOk();

        $this->actingAs($f['dispatcher'], 'sanctum')->postJson("/api/erp/fleet/trips/{$mine}/close")->assertOk()
            ->assertJsonPath('data.costs.fuel', 186000)->assertJsonPath('data.costs.expenses', 0);
        $this->assertArrayNotHasKey('fleet_tolls', $this->lines($f, $mine, 'close'), 'A rejected expense never reaches the books.');
    }

    public function test_fixed_costs_are_allocated_to_trips_once_and_never_beyond_what_a_month_costs(): void
    {
        // Mid-month, so both trips fall inside one month whatever day the suite runs.
        $this->travelTo(now()->startOfMonth()->addDays(14)->setTime(12, 0));
        $f = $this->fleet();
        // 3,000,000 a month, expected to run 5,000 km.
        FleetVehicle::acrossTenants()->whereKey($f['truck']->id)->update(['allocation_basis' => 'km', 'expected_monthly_km' => 5000]);
        $trip = ['cost_option' => 'included', 'vehicle_id' => $f['truck']->id, 'driver_id' => $f['driver']->id];

        $first = $this->runTrip($f, $trip, 10000, 14000);
        $this->actingAs($f['fleet_manager'], 'sanctum')->postJson("/api/erp/fleet/trips/{$first}/close")->assertOk()
            ->assertJsonPath('data.costs.fixed', 2400000);

        $second = $this->runTrip($f, $trip, 14000, 18000);
        $this->actingAs($f['fleet_manager'], 'sanctum')->postJson("/api/erp/fleet/trips/{$second}/close")->assertOk()
            ->assertJsonPath('data.costs.fixed', 600000);

        $this->assertSame(3000000.0, (float) FleetCostAllocation::acrossTenants()->where('vehicle_id', $f['truck']->id)->sum('amount'));
        $this->assertSame(2, FleetCostAllocation::acrossTenants()->count());
        // Allocations are a management figure: they never post a journal of their own.
        $this->assertSame(0, $this->journalCount($second), 'A trip with no cash costs posts nothing.');
    }

    public function test_a_service_posts_its_cost_once_and_moves_its_schedule_on(): void
    {
        $f = $this->fleet();
        $this->actingAs($f['fleet_manager'], 'sanctum');

        $schedule = $this->postJson('/api/erp/fleet/schedules', [
            'vehicle_id' => $f['truck']->id, 'title' => 'Engine oil and filters', 'interval_km' => 10000,
            'last_done_odometer' => 1000, 'interval_days' => 90, 'last_done_date' => now()->subDays(100)->toDateString(),
        ])->assertCreated()->json('data.id');
        $this->getJson('/api/erp/fleet/schedules')->assertJsonPath('data.0.state', 'overdue');

        $garage = app(TenantContext::class)->forCompany($f['company'], fn () => Supplier::create(['code' => 'GAR-1', 'name' => 'Kariakoo Motors']));
        $id = $this->postJson('/api/erp/fleet/services', [
            'vehicle_id' => $f['truck']->id, 'schedule_id' => $schedule, 'service_date' => now()->toDateString(),
            'odometer' => 10050, 'work_done' => 'Oil, oil filter, fuel filter', 'cost' => 450000, 'supplier_id' => $garage->id,
        ])->assertCreated()->assertJsonPath('data.status', 'draft')->json('data.id');

        $this->postJson("/api/erp/fleet/services/{$id}/post")->assertOk()->assertJsonPath('data.status', 'posted');
        $this->postJson("/api/erp/fleet/services/{$id}/post")->assertStatus(422);

        $entries = JournalEntry::acrossTenants()->with('lines.account')->where('source_type', 'FleetServiceRecord')->where('source_id', $id)->get();
        $this->assertCount(1, $entries);
        $this->assertSame(450000.0, (float) $entries[0]->lines->firstWhere('account.system_key', 'vehicle_maintenance')->debit);
        $this->assertSame(450000.0, (float) $entries[0]->lines->firstWhere('account.system_key', 'payable')->credit);

        $moved = FleetMaintenanceSchedule::acrossTenants()->find($schedule);
        $this->assertSame(20050.0, (float) $moved->next_due_odometer);
        $this->assertSame(now()->addDays(90)->toDateString(), $moved->next_due_date->toDateString());

        // Downtime takes the vehicle off the road and gives it back.
        $down = $this->postJson('/api/erp/fleet/downtimes', ['vehicle_id' => $f['truck']->id, 'reason' => 'breakdown'])->assertCreated()->json('data.id');
        $this->assertSame('out_of_service', FleetVehicle::acrossTenants()->find($f['truck']->id)->status);
        $this->plan($f, ['cost_option' => 'included', 'vehicle_id' => $f['truck']->id, 'driver_id' => $f['driver']->id])->assertStatus(422);
        $this->actingAs($f['fleet_manager'], 'sanctum')->postJson("/api/erp/fleet/downtimes/{$down}/end")->assertOk();
        $this->assertSame('available', FleetVehicle::acrossTenants()->find($f['truck']->id)->status);

        // One tyre per position.
        $this->postJson('/api/erp/fleet/tyres', ['vehicle_id' => $f['truck']->id, 'position' => 'Front left', 'serial_number' => 'BR-1'])->assertCreated();
        $this->postJson('/api/erp/fleet/tyres', ['vehicle_id' => $f['truck']->id, 'position' => 'Front left', 'serial_number' => 'BR-2'])->assertStatus(422);
    }

    public function test_permissions_follow_the_role(): void
    {
        $f = $this->fleet();
        $ceo = $f['ceo'];

        $this->actingAs($ceo, 'sanctum')->getJson('/api/erp/fleet/vehicles')->assertOk()->assertJsonCount(3, 'data');
        $this->postJson('/api/erp/fleet/vehicles', ['registration_number' => 'T 1 NEW', 'type' => 'truck', 'ownership' => 'owned'])->assertForbidden();
        $this->plan($f, ['cost_option' => 'included', 'vehicle_id' => $f['truck']->id, 'driver_id' => $f['driver']->id], 'ceo')->assertForbidden();

        $id = $this->plan($f, ['cost_option' => 'included', 'vehicle_id' => $f['truck']->id, 'driver_id' => $f['driver']->id])->assertCreated()->json('data.id');
        // A dispatcher plans trips but does not issue fuel or approve.
        $this->postJson("/api/erp/fleet/trips/{$id}/fuel", ['litres' => 10, 'price_per_litre' => 3000, 'account_id' => $f['cash']->id])->assertForbidden();
        $this->getJson('/api/erp/fleet/pending')->assertForbidden();

        // The storekeeper has no fleet access at all.
        $this->actingAs($f['storekeeper'], 'sanctum')->getJson('/api/erp/fleet/overview')->assertForbidden();

        $this->actingAs($f['fleet_manager'], 'sanctum')->postJson('/api/erp/fleet/vehicles', [
            'registration_number' => 'T 1 NEW', 'type' => 'truck', 'ownership' => 'hired',
        ])->assertStatus(422)->assertJsonValidationErrors(['supplier_id', 'hire_rate_basis', 'hire_rate']);

        // Cash for a payment must come from a cash or bank account.
        $sales = app(TenantContext::class)->forCompany($f['company'], fn () => Account::where('system_key', 'sales')->first());
        $this->postJson("/api/erp/fleet/trips/{$id}/fuel", ['litres' => 10, 'price_per_litre' => 3000, 'account_id' => $sales->id])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, '1100 to 1299'));
    }

    public function test_another_companys_fleet_is_invisible_and_unusable(): void
    {
        $mine = $this->fleet('Safari Freight');
        $theirs = $this->fleet('Zamani Logistics');
        $theirTrip = $this->plan($theirs, ['cost_option' => 'included', 'vehicle_id' => $theirs['truck']->id, 'driver_id' => $theirs['driver']->id])->json('data.id');

        $this->actingAs($mine['fleet_manager'], 'sanctum');
        $this->getJson("/api/erp/fleet/vehicles/{$theirs['truck']->id}")->assertNotFound();
        $this->getJson("/api/erp/fleet/trips/{$theirTrip}")->assertNotFound();
        $this->postJson("/api/erp/fleet/trips/{$theirTrip}/dispatch")->assertNotFound();
        $this->getJson('/api/erp/fleet/trips')->assertOk()->assertJsonCount(0, 'data');

        $this->plan($mine, ['cost_option' => 'included', 'vehicle_id' => $theirs['truck']->id, 'driver_id' => $theirs['driver']->id], 'fleet_manager')
            ->assertStatus(422)->assertJsonValidationErrors(['vehicle_id', 'driver_id']);

        // Their driver cannot reach my trips through my-trips either.
        $myTrip = $this->plan($mine, ['cost_option' => 'included', 'vehicle_id' => $mine['truck']->id, 'driver_id' => $mine['driver']->id])->json('data.id');
        $this->actingAs($theirs['driver_user'], 'sanctum')->getJson("/api/erp/fleet/my-trips/{$myTrip}")->assertNotFound();
    }

    public function test_every_fleet_screen_reads_for_the_fleet_manager(): void
    {
        $this->travelTo(now()->startOfMonth()->addDays(14)->setTime(12, 0));
        $f = $this->fleet();
        $id = $this->runTrip($f, ['cost_option' => 'included', 'vehicle_id' => $f['truck']->id, 'driver_id' => $f['driver']->id], 10000, 10200, [60]);
        $this->actingAs($f['fleet_manager'], 'sanctum')->postJson("/api/erp/fleet/trips/{$id}/close")->assertOk();

        foreach ([
            'overview', 'lookups', 'reports/profitability', 'vehicles', "vehicles/{$f['truck']->id}", 'drivers',
            "drivers/{$f['driver']->id}", 'standards', 'trips', "trips/{$id}", 'fuel', 'pending', 'schedules',
            'services', 'tyres', 'downtimes', 'driver-candidates',
        ] as $path) {
            $this->getJson("/api/erp/fleet/{$path}")->assertOk();
        }

        $this->getJson("/api/erp/fleet/trips/{$id}")->assertJsonCount(1, 'data.journals')->assertJsonPath('data.costs.fixed', fn ($v) => $v > 0);
        $this->actingAs($f['driver_user'], 'sanctum')->getJson("/api/erp/fleet/my-trips/{$id}")->assertOk()->assertJsonMissingPath('data.journals');
        $this->getJson('/api/erp/fleet/my-trips/lookups')->assertOk()->assertJsonStructure(['data' => ['accounts', 'suppliers']]);
    }
}
