<?php

namespace App\Services\Erp\Fleet;

use App\Models\Erp\Fleet\FleetCostAllocation;
use App\Models\Erp\Fleet\FleetDriver;
use App\Models\Erp\Fleet\FleetFuelIssue;
use App\Models\Erp\Fleet\FleetMaintenanceSchedule;
use App\Models\Erp\Fleet\FleetTrip;
use App\Models\Erp\Fleet\FleetTripExpense;
use App\Models\Erp\Fleet\FleetVehicle;
use Carbon\CarbonImmutable;

/**
 * The fleet overview and trip profitability, read from the stored trips,
 * entries and allocations, so the report and the books tell the same story.
 */
class FleetReports
{
    public function __construct(private readonly FleetTrips $trips) {}

    /** @return array<string, mixed> */
    public function overview(): array
    {
        $today = today();
        $soon = $today->copy()->addDays(30);

        $byStatus = FleetVehicle::query()->where('is_active', true)
            ->selectRaw('status, count(*) as n')->groupBy('status')->pluck('n', 'status');

        $tripsToday = FleetTrip::query()->with(['vehicle:id,registration_number', 'driver.user:id,name', 'customer:id,name'])
            ->where(fn ($q) => $q->whereDate('planned_start', $today)
                ->orWhere('status', FleetTrip::STATUS_DISPATCHED))
            ->whereNotIn('status', [FleetTrip::STATUS_CANCELLED])
            ->orderBy('planned_start')->limit(20)->get();

        $variance = FleetTrip::query()->with('vehicle:id,registration_number')
            ->where('fuel_over_standard', true)->where('status', FleetTrip::STATUS_COMPLETED)
            ->latest('actual_end')->limit(20)->get();

        $expiring = [];
        foreach (FleetVehicle::query()->where('is_active', true)->get() as $v) {
            foreach (['insurance' => $v->insurance_expiry, 'road_licence' => $v->road_licence_expiry] as $kind => $date) {
                if ($date && $date->lte($soon)) {
                    $expiring[] = ['kind' => $kind, 'subject' => $v->registration_number, 'vehicle_id' => $v->id, 'driver_id' => null, 'date' => $date->toDateString(), 'expired' => $date->lt($today)];
                }
            }
        }
        foreach (FleetDriver::query()->with('user:id,name')->where('is_active', true)->whereNotNull('licence_expiry')->whereDate('licence_expiry', '<=', $soon)->get() as $d) {
            $expiring[] = ['kind' => 'driving_licence', 'subject' => $d->user?->name, 'vehicle_id' => null, 'driver_id' => $d->id, 'date' => $d->licence_expiry->toDateString(), 'expired' => $d->licence_expiry->lt($today)];
        }
        usort($expiring, fn ($a, $b) => strcmp($a['date'], $b['date']));

        return [
            'vehicles' => [
                'total' => (int) $byStatus->sum(),
                'by_status' => collect(FleetVehicle::STATUSES)->mapWithKeys(fn ($s) => [$s => (int) ($byStatus[$s] ?? 0)]),
            ],
            'trips_today' => $tripsToday,
            'fuel_alerts' => $variance,
            'expiring' => $expiring,
            'maintenance_due' => $this->maintenanceDue(),
            'pending_entries' => FleetFuelIssue::query()->where('status', FleetFuelIssue::PENDING)->count()
                + FleetTripExpense::query()->where('status', FleetFuelIssue::PENDING)->count(),
            'month' => $this->monthFigures(),
        ];
    }

    /** @return list<array<string, mixed>> schedules due within 14 days or 1,000 km, or overdue */
    public function maintenanceDue(): array
    {
        return FleetMaintenanceSchedule::query()->with('vehicle:id,registration_number,odometer')->where('is_active', true)->get()
            ->map(fn ($s) => [...$s->toArray(), 'state' => $s->dueState((float) $s->vehicle?->odometer)])
            ->filter(fn ($s) => $s['state'] !== 'ok')
            ->sortBy(fn ($s) => $s['state'] === 'overdue' ? 0 : 1)
            ->values()->all();
    }

    /** @return array<string, float|int> */
    private function monthFigures(): array
    {
        $from = today()->startOfMonth();
        $closed = FleetTrip::query()->where('status', FleetTrip::STATUS_CLOSED)->where('closed_at', '>=', $from)
            ->with(['fuelIssues', 'expenses', 'allocations'])->get();
        $rows = $closed->map(fn ($t) => $this->trips->costs($t));

        return [
            'trips_closed' => $closed->count(),
            'revenue' => round($rows->sum('revenue'), 2),
            'cost' => round($rows->sum('total_cost'), 2),
            'profit' => round($rows->sum('profit'), 2),
            'litres' => round((float) FleetFuelIssue::query()->where('status', FleetFuelIssue::APPROVED)->where('issue_date', '>=', $from)->sum('litres'), 1),
        ];
    }

    /**
     * Closed trips between two dates with their revenue, costs and profit,
     * and the same per vehicle, including the fixed cost trips left unabsorbed.
     *
     * @return array<string, mixed>
     */
    public function profitability(?string $from, ?string $to, ?int $vehicleId): array
    {
        $from = $from ? CarbonImmutable::parse($from)->startOfDay() : CarbonImmutable::today()->subDays(30);
        $to = $to ? CarbonImmutable::parse($to)->endOfDay() : CarbonImmutable::now()->endOfDay();

        $trips = FleetTrip::query()
            ->with(['vehicle:id,registration_number,ownership', 'driver.user:id,name', 'customer:id,name', 'fuelIssues', 'expenses', 'allocations'])
            ->where('status', FleetTrip::STATUS_CLOSED)
            ->whereBetween('actual_end', [$from, $to])
            ->when($vehicleId, fn ($q, $v) => $q->where('vehicle_id', $v))
            ->orderBy('actual_end')->get();

        $rows = $trips->map(fn (FleetTrip $t) => [
            'id' => $t->id, 'number' => $t->number, 'cost_option' => $t->cost_option,
            'origin' => $t->origin, 'destination' => $t->destination, 'date' => $t->actual_end?->toDateString(),
            'vehicle' => $t->vehicle?->registration_number ?? $t->external_vehicle, 'vehicle_id' => $t->vehicle_id,
            'driver' => $t->driver?->user?->name, 'customer' => $t->customer?->name,
            ...$this->trips->costs($t),
        ]);

        $periods = [];
        for ($m = $from->startOfMonth(); $m->lte($to); $m = $m->addMonth()) {
            $periods[] = $m->format('Y-m');
        }

        $vehicles = FleetVehicle::query()->when($vehicleId, fn ($q, $v) => $q->whereKey($v))->orderBy('registration_number')->get()
            ->map(function (FleetVehicle $v) use ($rows, $periods) {
                $own = $rows->where('vehicle_id', $v->id);
                $absorbed = (float) FleetCostAllocation::query()->where('vehicle_id', $v->id)->whereIn('period', $periods)->sum('amount');
                $fixed = $v->isHired() ? 0.0 : round($v->monthlyFixedCost() * count($periods), 2);

                return [
                    'id' => $v->id, 'registration_number' => $v->registration_number, 'ownership' => $v->ownership,
                    'trips' => $own->count(),
                    'distance_km' => round($own->sum('distance_km'), 1),
                    'revenue' => round($own->sum('revenue'), 2),
                    'fuel' => round($own->sum('fuel'), 2),
                    'expenses' => round($own->sum('expenses'), 2),
                    'hire' => round($own->sum('hire'), 2),
                    'fixed' => round($own->sum('fixed'), 2),
                    'total_cost' => round($own->sum('total_cost'), 2),
                    'profit' => round($own->sum('profit'), 2),
                    'fixed_budget' => $fixed,
                    'unabsorbed_fixed' => round(max(0, $fixed - $absorbed), 2),
                ];
            })
            ->filter(fn ($v) => $v['trips'] > 0 || $v['fixed_budget'] > 0)->values();

        $totals = collect(['revenue', 'fuel', 'expenses', 'hire', 'fixed', 'total_cost', 'profit', 'distance_km'])
            ->mapWithKeys(fn ($k) => [$k => round($rows->sum($k), 2)]);

        return [
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'trips' => $rows->values(),
            'vehicles' => $vehicles,
            'totals' => $totals,
        ];
    }
}
