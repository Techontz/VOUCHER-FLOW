<?php

namespace App\Services\Erp\Fleet;

use App\Models\Erp\Customer;
use App\Models\Erp\Fleet\FleetCostAllocation;
use App\Models\Erp\Fleet\FleetDriver;
use App\Models\Erp\Fleet\FleetFuelIssue;
use App\Models\Erp\Fleet\FleetFuelStandard;
use App\Models\Erp\Fleet\FleetTrip;
use App\Models\Erp\Fleet\FleetTripExpense;
use App\Models\Erp\Fleet\FleetVehicle;
use App\Models\Erp\Supplier;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Trips from plan to close.
 *
 *   planned     editable; nothing is committed
 *   dispatched  the vehicle is out (on_trip) with its odometer reading
 *   completed   back, odometer in; fuel is compared with the standard
 *   closed      costs settled: fixed costs allocated and the ledger posted, once
 *   cancelled   from planned or dispatched, before any cost was approved
 *
 * The four transport cost options decide what a trip may carry and post:
 *   customer_vehicle  nothing: the customer's own truck, no company cost
 *   charged           company vehicle; Dr receivable / Cr transport revenue for the charge
 *   included          company vehicle; costs only, the price already carries transport
 *   hired             hired vehicle; Dr vehicle hire / Cr payable to its owner, once.
 *                     A wet hire takes no fuel, and a hired truck absorbs no fixed
 *                     costs, so nothing the hire already pays for is counted again.
 *
 * Closing posts one entry for the costs (Dr fuel and expense accounts, Cr the
 * cash, bank or payable they were paid from) and, when the customer is
 * charged, one for the revenue. Both are keyed to the trip.
 */
class FleetTrips
{
    public function __construct(
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function create(array $data, User $actor): FleetTrip
    {
        return DB::transaction(function () use ($data, $actor) {
            $trip = FleetTrip::create([
                ...$this->attributes($data),
                'number' => $this->numbers->next('TRP'),
                'status' => FleetTrip::STATUS_PLANNED,
                'created_by' => $actor->id,
            ]);

            $this->audit->log('fleet.trip.created', "Planned trip {$trip->number}: {$trip->origin} to {$trip->destination}", $trip, actor: $actor);

            return $trip;
        });
    }

    /** @param  array<string, mixed>  $data */
    public function update(FleetTrip $trip, array $data, User $actor): FleetTrip
    {
        return DB::transaction(function () use ($trip, $data, $actor) {
            $locked = $this->lock($trip);
            $this->assertStatus($locked, [FleetTrip::STATUS_PLANNED], 'edited');

            $locked->update($this->attributes($data));
            $this->audit->log('fleet.trip.updated', "Edited planned trip {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    public function dispatch(FleetTrip $trip, ?float $odometerOut, ?string $at, User $actor): FleetTrip
    {
        return DB::transaction(function () use ($trip, $odometerOut, $at, $actor) {
            $locked = $this->lock($trip);
            $this->assertStatus($locked, [FleetTrip::STATUS_PLANNED], 'dispatched');

            $updates = [
                'status' => FleetTrip::STATUS_DISPATCHED,
                'actual_start' => $at ?? now(),
                'dispatched_by' => $actor->id,
                'dispatched_at' => now(),
            ];

            if ($locked->vehicle_id) {
                $vehicle = FleetVehicle::query()->whereKey($locked->vehicle_id)->lockForUpdate()->firstOrFail();

                if ($vehicle->status !== FleetVehicle::STATUS_AVAILABLE) {
                    throw new RuntimeException("{$vehicle->registration_number} is ".str_replace('_', ' ', $vehicle->status).' and cannot be dispatched.');
                }

                $reading = $odometerOut ?? (float) $vehicle->odometer;

                if (! $vehicle->isHired() && $reading < (float) $vehicle->odometer) {
                    throw new RuntimeException("The odometer reading out ({$reading} km) is below what {$vehicle->registration_number} last recorded ({$vehicle->odometer} km).");
                }

                $updates['odometer_out'] = $reading;
                $vehicle->update(['status' => FleetVehicle::STATUS_ON_TRIP]);
            }

            if ($locked->driver_id) {
                $driver = FleetDriver::query()->with('user:id,name')->findOrFail($locked->driver_id);

                if ($driver->licence_expiry && $driver->licence_expiry->lt(today())) {
                    throw new RuntimeException("{$driver->user?->name}'s driving licence expired on {$driver->licence_expiry->toDateString()}.");
                }
            }

            $locked->update($updates);
            $this->audit->log('fleet.trip.dispatched', "Dispatched trip {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    public function complete(FleetTrip $trip, ?float $odometerIn, ?string $at, User $actor): FleetTrip
    {
        return DB::transaction(function () use ($trip, $odometerIn, $at, $actor) {
            $locked = $this->lock($trip);
            $this->assertStatus($locked, [FleetTrip::STATUS_DISPATCHED], 'completed');

            $end = $at ? CarbonImmutable::parse($at) : CarbonImmutable::now();

            if ($locked->actual_start && $end->lt($locked->actual_start)) {
                throw new RuntimeException('The trip cannot end before it started.');
            }

            if ($locked->usesCompanyVehicle() && $odometerIn === null) {
                throw new RuntimeException('Enter the odometer reading the vehicle came back with.');
            }

            if ($odometerIn !== null && $locked->odometer_out !== null && $odometerIn < (float) $locked->odometer_out) {
                throw new RuntimeException("The odometer in ({$odometerIn} km) cannot be below the odometer out ({$locked->odometer_out} km).");
            }

            $locked->fill([
                'status' => FleetTrip::STATUS_COMPLETED,
                'actual_end' => $end,
                'odometer_in' => $odometerIn,
                'completed_by' => $actor->id,
                'completed_at' => now(),
            ]);

            if ($locked->vehicle_id) {
                $vehicle = FleetVehicle::query()->whereKey($locked->vehicle_id)->lockForUpdate()->firstOrFail();
                $vehicle->status = FleetVehicle::STATUS_AVAILABLE;

                if ($odometerIn !== null && $odometerIn > (float) $vehicle->odometer) {
                    $vehicle->odometer = $odometerIn;
                }

                $vehicle->save();

                if ($locked->cost_option === FleetTrip::OPTION_HIRED) {
                    $locked->hire_cost = $this->hireCost($locked, $vehicle);
                }
            }

            $this->evaluateFuel($locked, false);
            $locked->save();

            $this->audit->log('fleet.trip.completed', "Completed trip {$locked->number}".($locked->fuel_over_standard ? ', fuel over standard' : ''), $locked, actor: $actor);

            return $locked;
        });
    }

    /**
     * Settles a completed trip: every entry decided, the fuel variance
     * accepted by someone allowed to, fixed costs allocated and the ledger
     * posted, all in one transaction under the trip's row lock.
     */
    public function close(FleetTrip $trip, ?string $note, User $actor): FleetTrip
    {
        return DB::transaction(function () use ($trip, $note, $actor) {
            $locked = $this->lock($trip);
            $this->assertStatus($locked, [FleetTrip::STATUS_COMPLETED], 'closed');

            $pending = $locked->fuelIssues()->where('status', FleetFuelIssue::PENDING)->count()
                + $locked->expenses()->where('status', FleetFuelIssue::PENDING)->count();

            if ($pending > 0) {
                throw new RuntimeException("{$locked->number} has {$pending} fuel or expense ".($pending === 1 ? 'entry' : 'entries').' waiting for approval. Approve or reject them first.');
            }

            $this->evaluateFuel($locked, true);

            if ($locked->fuel_over_standard) {
                if (! $actor->hasPermission('fleet.approve')) {
                    throw new RuntimeException(sprintf(
                        '%s used %s litres against a standard of %s (%+.1f%%), over the %s%% tolerance. Someone who approves fleet costs must close it.',
                        $locked->number, $this->num($locked->actual_litres), $this->num($locked->standard_litres),
                        (float) $locked->fuel_variance_percent, $this->num($locked->fuel_tolerance_percent),
                    ));
                }

                $locked->variance_approved_by = $actor->id;
                $locked->variance_approved_at = now();
                $locked->variance_note = $note ? mb_substr($note, 0, 255) : null;
            }

            $this->allocateFixedCosts($locked);

            $locked->status = FleetTrip::STATUS_CLOSED;
            $locked->closed_by = $actor->id;
            $locked->closed_at = now();
            $locked->save();

            $this->postToLedger($locked, $actor);
            $this->audit->log('fleet.trip.closed', "Closed trip {$locked->number}".($locked->variance_approved_by ? ', fuel variance approved' : ''), $locked, actor: $actor);

            return $locked;
        });
    }

    public function cancel(FleetTrip $trip, string $reason, User $actor): FleetTrip
    {
        return DB::transaction(function () use ($trip, $reason, $actor) {
            $locked = $this->lock($trip);
            $this->assertStatus($locked, [FleetTrip::STATUS_PLANNED, FleetTrip::STATUS_DISPATCHED], 'cancelled');

            $approved = $locked->fuelIssues()->where('status', FleetFuelIssue::APPROVED)->exists()
                || $locked->expenses()->where('status', FleetFuelIssue::APPROVED)->exists();

            if ($approved) {
                throw new RuntimeException("{$locked->number} already carries approved costs. Complete and close it so they reach the books.");
            }

            if ($locked->status === FleetTrip::STATUS_DISPATCHED && $locked->vehicle_id) {
                FleetVehicle::query()->whereKey($locked->vehicle_id)->where('status', FleetVehicle::STATUS_ON_TRIP)
                    ->update(['status' => FleetVehicle::STATUS_AVAILABLE]);
            }

            $locked->fuelIssues()->where('status', FleetFuelIssue::PENDING)->update(['status' => FleetFuelIssue::REJECTED, 'rejection_reason' => 'Trip cancelled']);
            $locked->expenses()->where('status', FleetFuelIssue::PENDING)->update(['status' => FleetFuelIssue::REJECTED, 'rejection_reason' => 'Trip cancelled']);
            $locked->update(['status' => FleetTrip::STATUS_CANCELLED, 'cancel_reason' => mb_substr($reason, 0, 255)]);

            $this->audit->log('fleet.trip.cancelled', "Cancelled trip {$locked->number}: {$reason}", $locked, actor: $actor);

            return $locked;
        });
    }

    /* ------------------------------------------------------------ fuel and expenses */

    /** @param  array<string, mixed>  $data */
    public function recordFuel(FleetTrip $trip, array $data, User $actor): FleetFuelIssue
    {
        return DB::transaction(function () use ($trip, $data, $actor) {
            $locked = $this->lock($trip);
            $this->assertCostsOpen($locked);
            $vehicle = $locked->vehicle;

            if ($locked->cost_option === FleetTrip::OPTION_HIRED && $vehicle?->hire_includes_fuel) {
                throw new RuntimeException("{$vehicle->registration_number} is hired with fuel: its owner pays for fuel, so the company cannot pay for it as well.");
            }

            $litres = (float) $data['litres'];
            $price = (float) $data['price_per_litre'];

            if ($litres <= 0 || $price <= 0) {
                throw new RuntimeException('Enter the litres and the price per litre.');
            }

            $approved = $actor->hasPermission('fleet.approve');
            $issue = FleetFuelIssue::create([
                ...PaymentSource::resolve($data),
                'trip_id' => $locked->id,
                'vehicle_id' => $locked->vehicle_id,
                'issue_date' => $data['issue_date'] ?? today()->toDateString(),
                'litres' => $litres,
                'price_per_litre' => $price,
                'amount' => round($litres * $price, 2),
                'station' => $data['station'] ?? null,
                'receipt_number' => $data['receipt_number'] ?? null,
                'odometer' => $data['odometer'] ?? null,
                'status' => $approved ? FleetFuelIssue::APPROVED : FleetFuelIssue::PENDING,
                'recorded_by' => $actor->id,
                'approved_by' => $approved ? $actor->id : null,
                'approved_at' => $approved ? now() : null,
            ]);

            $this->audit->log('fleet.fuel.recorded', "Fuel {$this->num($litres)} L on {$locked->number}".($approved ? '' : ', awaiting approval'), $issue, actor: $actor);
            $this->refreshVariance($locked);

            return $issue;
        });
    }

    /** @param  array<string, mixed>  $data */
    public function recordExpense(FleetTrip $trip, array $data, User $actor): FleetTripExpense
    {
        return DB::transaction(function () use ($trip, $data, $actor) {
            $locked = $this->lock($trip);
            $this->assertCostsOpen($locked);

            $type = $data['type'];
            $quantity = (float) ($data['quantity'] ?? 1);
            $rate = isset($data['rate']) && $data['rate'] !== '' ? (float) $data['rate'] : null;

            if ($type === 'allowance' && $rate === null) {
                $rate = (float) ($locked->driver?->daily_allowance ?? 0);
            }

            if ($quantity <= 0 || ! $rate || $rate <= 0) {
                throw new RuntimeException($type === 'allowance'
                    ? 'Enter the number of days and the daily allowance.'
                    : 'Enter the amount.');
            }

            $approved = $actor->hasPermission('fleet.approve');
            $expense = FleetTripExpense::create([
                ...PaymentSource::resolve($data),
                'trip_id' => $locked->id,
                'type' => $type,
                'description' => $data['description'] ?? null,
                'expense_date' => $data['expense_date'] ?? today()->toDateString(),
                'quantity' => $quantity,
                'rate' => $rate,
                'amount' => round($quantity * $rate, 2),
                'receipt_number' => $data['receipt_number'] ?? null,
                'status' => $approved ? FleetFuelIssue::APPROVED : FleetFuelIssue::PENDING,
                'recorded_by' => $actor->id,
                'approved_by' => $approved ? $actor->id : null,
                'approved_at' => $approved ? now() : null,
            ]);

            $this->audit->log('fleet.expense.recorded', ucfirst($type)." on {$locked->number}".($approved ? '' : ', awaiting approval'), $expense, actor: $actor);

            return $expense;
        });
    }

    /** Approves or rejects a fuel issue or expense waiting on a trip that is still open. */
    public function decide(FleetFuelIssue|FleetTripExpense $entry, bool $approve, ?string $reason, User $actor): FleetFuelIssue|FleetTripExpense
    {
        return DB::transaction(function () use ($entry, $approve, $reason, $actor) {
            $trip = $this->lock($entry->trip);
            $locked = $entry::query()->whereKey($entry->id)->lockForUpdate()->firstOrFail();

            if ($locked->status !== FleetFuelIssue::PENDING) {
                throw new RuntimeException("This entry is already {$locked->status}.");
            }

            if (in_array($trip->status, [FleetTrip::STATUS_CLOSED, FleetTrip::STATUS_CANCELLED], true)) {
                throw new RuntimeException("{$trip->number} is {$trip->status}.");
            }

            if (! $approve && blank($reason)) {
                throw new RuntimeException('Say why it is rejected.');
            }

            $locked->update([
                'status' => $approve ? FleetFuelIssue::APPROVED : FleetFuelIssue::REJECTED,
                'approved_by' => $actor->id,
                'approved_at' => now(),
                'rejection_reason' => $approve ? null : mb_substr((string) $reason, 0, 255),
            ]);

            $kind = $locked instanceof FleetFuelIssue ? 'fuel' : 'expense';
            $this->audit->log("fleet.{$kind}.".($approve ? 'approved' : 'rejected'), ucfirst($kind)." on {$trip->number} ".($approve ? 'approved' : "rejected: {$reason}"), $locked, actor: $actor);

            if ($locked instanceof FleetFuelIssue) {
                $this->refreshVariance($trip);
            }

            return $locked;
        });
    }

    /* ------------------------------------------------------------ fuel against the standard */

    /** The most specific active standard: this vehicle on this route, then the route, then the vehicle. */
    public function standardFor(FleetTrip $trip): ?FleetFuelStandard
    {
        $route = fn (FleetFuelStandard $s) => $s->origin && $s->destination && (
            (strcasecmp($s->origin, $trip->origin) === 0 && strcasecmp($s->destination, $trip->destination) === 0)
            || (strcasecmp($s->origin, $trip->destination) === 0 && strcasecmp($s->destination, $trip->origin) === 0)
        );

        $candidates = FleetFuelStandard::query()->where('is_active', true)
            ->where(fn ($q) => $q->whereNull('vehicle_id')->orWhere('vehicle_id', $trip->vehicle_id))
            ->get();

        return $candidates->filter(fn ($s) => $s->vehicle_id && $route($s))->first()
            ?? $candidates->filter(fn ($s) => ! $s->vehicle_id && $route($s))->first()
            ?? $candidates->filter(fn ($s) => $s->vehicle_id && ! $s->origin && ! $s->destination)->first();
    }

    /**
     * Compares the fuel issued with what the standard allows. At completion
     * every entry not rejected counts; at close only the approved ones do.
     */
    public function evaluateFuel(FleetTrip $trip, bool $approvedOnly): void
    {
        $statuses = $approvedOnly ? [FleetFuelIssue::APPROVED] : [FleetFuelIssue::APPROVED, FleetFuelIssue::PENDING];
        $litres = (float) $trip->fuelIssues()->whereIn('status', $statuses)->sum('litres');
        $standard = $trip->vehicle_id ? $this->standardFor($trip) : null;
        $allowed = $standard?->litresFor($trip->distance());

        $trip->actual_litres = $litres;
        $trip->standard_litres = $allowed;
        $trip->fuel_tolerance_percent = $standard?->tolerance_percent;

        if (! $allowed || $allowed <= 0) {
            $trip->fuel_variance_percent = null;
            $trip->fuel_over_standard = false;

            return;
        }

        $trip->fuel_variance_percent = round(($litres - $allowed) / $allowed * 100, 2);
        $trip->fuel_over_standard = $litres > $allowed * (1 + (float) $standard->tolerance_percent / 100) + 0.0005;
    }

    /** Keeps the variance shown on a completed trip current as entries arrive. */
    private function refreshVariance(FleetTrip $trip): void
    {
        if ($trip->status === FleetTrip::STATUS_COMPLETED) {
            $this->evaluateFuel($trip, false);
            $trip->save();
        }
    }

    /* ------------------------------------------------------------ costs */

    /** What the hire of a hired vehicle costs for this trip, on the owner's basis. */
    public function hireCost(FleetTrip $trip, FleetVehicle $vehicle): float
    {
        $rate = (float) $vehicle->hire_rate;

        return round(match ($vehicle->hire_rate_basis) {
            'per_km' => $rate * $trip->distance(),
            'per_day' => $rate * $this->tripDays($trip),
            default => $rate,
        }, 2);
    }

    /** Calendar days the trip touched, at least one. */
    public function tripDays(FleetTrip $trip): int
    {
        $start = CarbonImmutable::parse($trip->actual_start ?? $trip->planned_start)->startOfDay();
        $end = CarbonImmutable::parse($trip->actual_end ?? $trip->planned_end ?? $start)->startOfDay();

        return max(1, (int) $start->diffInDays($end) + 1);
    }

    /**
     * Gives a closed trip its share of the vehicle's monthly fixed costs, one
     * row per month the trip touched. By days: the month's cost times the
     * trip's days over the month's days. By km: times the trip's km over the
     * km the vehicle is expected to run that month. A month is never
     * allocated beyond what it costs; anything trips do not absorb stays
     * visible as idle cost on the vehicle report.
     */
    public function allocateFixedCosts(FleetTrip $trip): void
    {
        if (! $trip->usesCompanyVehicle() || ! $trip->vehicle_id) {
            return;
        }

        // Serialises allocations for the vehicle, so two trips closing at
        // once cannot both take the last of a month.
        $vehicle = FleetVehicle::query()->whereKey($trip->vehicle_id)->lockForUpdate()->firstOrFail();
        $monthly = $vehicle->monthlyFixedCost();

        if ($vehicle->isHired() || $monthly <= 0) {
            return;
        }

        $start = CarbonImmutable::parse($trip->actual_start ?? $trip->planned_start)->startOfDay();
        $days = $this->tripDays($trip);
        $byKm = $vehicle->allocation_basis === 'km' && (float) $vehicle->expected_monthly_km > 0;
        $perPeriod = [];

        for ($i = 0; $i < $days; $i++) {
            $period = $start->addDays($i)->format('Y-m');
            $perPeriod[$period] = ($perPeriod[$period] ?? 0) + 1;
        }

        foreach ($perPeriod as $period => $periodDays) {
            $monthDays = CarbonImmutable::createFromFormat('Y-m-d', "{$period}-01")->daysInMonth;
            $share = $byKm ? round($trip->distance() * $periodDays / $days, 3) : $periodDays;
            $units = $byKm ? (float) $vehicle->expected_monthly_km : $monthDays;
            $already = (float) FleetCostAllocation::query()->where('vehicle_id', $vehicle->id)->where('period', $period)->sum('amount');
            $amount = min(round($monthly * $share / $units, 2), round($monthly - $already, 2));

            if ($amount <= 0) {
                continue;
            }

            FleetCostAllocation::create([
                'vehicle_id' => $vehicle->id,
                'trip_id' => $trip->id,
                'period' => $period,
                'basis' => $byKm ? 'km' : 'days',
                'share' => $share,
                'period_units' => $units,
                'monthly_fixed_cost' => $monthly,
                'amount' => $amount,
            ]);
        }
    }

    /**
     * Revenue and every cost of a trip. Rejected entries never count;
     * pending ones are shown apart until someone decides them.
     *
     * @return array<string, float>
     */
    public function costs(FleetTrip $trip): array
    {
        $fuel = $trip->relationLoaded('fuelIssues') ? $trip->fuelIssues : $trip->fuelIssues()->get();
        $expenses = $trip->relationLoaded('expenses') ? $trip->expenses : $trip->expenses()->get();
        $allocations = $trip->relationLoaded('allocations') ? $trip->allocations : $trip->allocations()->get();

        $sum = fn ($rows, string $status) => round((float) $rows->where('status', $status)->sum('amount'), 2);
        $revenue = in_array($trip->cost_option, [FleetTrip::OPTION_CHARGED, FleetTrip::OPTION_HIRED], true) ? (float) $trip->transport_charge : 0.0;
        $fuelCost = $sum($fuel, FleetFuelIssue::APPROVED);
        $expenseCost = $sum($expenses, FleetFuelIssue::APPROVED);
        $hire = (float) $trip->hire_cost;
        $fixed = round((float) $allocations->sum('amount'), 2);
        $total = round($fuelCost + $expenseCost + $hire + $fixed, 2);

        return [
            'revenue' => $revenue,
            'fuel' => $fuelCost,
            'expenses' => $expenseCost,
            'hire' => $hire,
            'fixed' => $fixed,
            'total_cost' => $total,
            'profit' => round($revenue - $total, 2),
            'pending' => round($sum($fuel, FleetFuelIssue::PENDING) + $sum($expenses, FleetFuelIssue::PENDING), 2),
            'distance_km' => $trip->distance(),
            'days' => $this->tripDays($trip),
        ];
    }

    /* ------------------------------------------------------------ ledger */

    private function postToLedger(FleetTrip $trip, User $actor): void
    {
        if (! BusinessConfig::of($this->tenant->company())->postsToLedger()) {
            return;
        }

        $date = ($trip->actual_end ?? now())->toDateString();
        $memo = "Trip {$trip->number}: {$trip->origin} to {$trip->destination}";
        $debits = [];
        $credits = [];
        $payable = [];

        $credit = function (Model $entry, float $amount) use (&$credits, &$payable) {
            if ($entry->account_id) {
                $credits[$entry->account_id] = ($credits[$entry->account_id] ?? 0) + $amount;
            } else {
                $payable[$entry->supplier_id] = ($payable[$entry->supplier_id] ?? 0) + $amount;
            }
        };

        foreach ($trip->fuelIssues()->where('status', FleetFuelIssue::APPROVED)->get() as $issue) {
            $debits['fuel'] = ($debits['fuel'] ?? 0) + (float) $issue->amount;
            $credit($issue, (float) $issue->amount);
        }

        foreach ($trip->expenses()->where('status', FleetFuelIssue::APPROVED)->get() as $expense) {
            $key = FleetTripExpense::ACCOUNTS[$expense->type] ?? 'fleet_trip_other';
            $debits[$key] = ($debits[$key] ?? 0) + (float) $expense->amount;
            $credit($expense, (float) $expense->amount);
        }

        if ($trip->cost_option === FleetTrip::OPTION_HIRED && (float) $trip->hire_cost > 0) {
            $debits['fleet_vehicle_hire'] = (float) $trip->hire_cost;
            $owner = $trip->vehicle?->supplier_id;
            $payable[$owner] = ($payable[$owner] ?? 0) + (float) $trip->hire_cost;
        }

        $lines = [];
        foreach ($debits as $key => $amount) {
            $lines[] = ['account' => $key, 'debit' => round($amount, 2), 'description' => $trip->number];
        }
        foreach ($credits as $accountId => $amount) {
            $lines[] = ['account_id' => $accountId, 'credit' => round($amount, 2), 'description' => $trip->number];
        }
        $names = Supplier::query()->whereIn('id', array_filter(array_keys($payable)))->pluck('name', 'id');
        foreach ($payable as $supplierId => $amount) {
            $lines[] = ['account' => 'payable', 'credit' => round($amount, 2), 'description' => trim("{$trip->number} ".($names[$supplierId] ?? ''))];
        }

        if (count($lines) >= 2) {
            $this->journal->post($lines, $memo, $date, $trip, 'close', $actor);
        }

        $charge = (float) $trip->transport_charge;

        if ($charge > 0 && in_array($trip->cost_option, [FleetTrip::OPTION_CHARGED, FleetTrip::OPTION_HIRED], true)) {
            $customer = Customer::query()->whereKey($trip->customer_id)->value('name');
            $this->journal->post([
                ['account' => 'receivable', 'debit' => $charge, 'description' => trim("{$trip->number} {$customer}")],
                ['account' => 'transport_revenue', 'credit' => $charge, 'description' => $trip->number],
            ], "Transport charge, {$memo}", $date, $trip, 'charge', $actor);
        }
    }

    /* ------------------------------------------------------------ rules */

    /**
     * Turns a request into trip columns, refusing any combination the cost
     * option does not allow.
     *
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    private function attributes(array $data): array
    {
        $option = $data['cost_option'];
        $vehicle = ! empty($data['vehicle_id']) ? FleetVehicle::query()->find($data['vehicle_id']) : null;
        $driver = ! empty($data['driver_id']) ? FleetDriver::query()->find($data['driver_id']) : null;
        $charge = round((float) ($data['transport_charge'] ?? 0), 2);
        $customerId = $data['customer_id'] ?? null;

        if ($option === FleetTrip::OPTION_CUSTOMER_VEHICLE) {
            if ($vehicle || $driver) {
                throw new RuntimeException('When the customer collects in their own vehicle, no company vehicle or driver goes on the trip.');
            }
            if (! $customerId) {
                throw new RuntimeException('Choose the customer collecting the goods.');
            }
            $charge = 0;
        } else {
            if (! $vehicle) {
                throw new RuntimeException('Choose the vehicle.');
            }
            if (! $vehicle->is_active || $vehicle->status === FleetVehicle::STATUS_OUT_OF_SERVICE) {
                throw new RuntimeException("{$vehicle->registration_number} is out of service.");
            }
            if ($option === FleetTrip::OPTION_HIRED && ! $vehicle->isHired()) {
                throw new RuntimeException("{$vehicle->registration_number} is a company vehicle; the hired option is for hired vehicles.");
            }
            if ($option !== FleetTrip::OPTION_HIRED && $vehicle->isHired()) {
                throw new RuntimeException("{$vehicle->registration_number} is hired: plan it under the hired vehicle option so the hire is counted once.");
            }
            if ($option !== FleetTrip::OPTION_HIRED && ! $driver) {
                throw new RuntimeException('Choose the driver.');
            }
            if ($driver && ! $driver->is_active) {
                throw new RuntimeException('That driver is inactive.');
            }
        }

        if ($option === FleetTrip::OPTION_CHARGED && $charge <= 0) {
            throw new RuntimeException('Enter the transport charge for the customer.');
        }

        if ($option === FleetTrip::OPTION_INCLUDED) {
            // Transport is in the product price: recording a charge would count the revenue twice.
            $charge = 0;
        }

        if ($charge > 0 && ! $customerId) {
            throw new RuntimeException('Choose the customer the transport is charged to.');
        }

        return [
            'cost_option' => $option,
            'vehicle_id' => $vehicle?->id,
            'driver_id' => $driver?->id,
            'external_vehicle' => $option === FleetTrip::OPTION_CUSTOMER_VEHICLE ? ($data['external_vehicle'] ?? null) : null,
            'customer_id' => $customerId,
            'origin' => $data['origin'],
            'destination' => $data['destination'],
            'distance_km' => $data['distance_km'] ?? 0,
            'planned_start' => $data['planned_start'],
            'planned_end' => $data['planned_end'] ?? null,
            'source_type' => $data['source_type'] ?? null,
            'source_id' => $data['source_id'] ?? null,
            'source_reference' => $data['source_reference'] ?? null,
            'cargo_description' => $data['cargo_description'] ?? null,
            'transport_charge' => $charge,
            'notes' => $data['notes'] ?? null,
        ];
    }

    private function assertCostsOpen(FleetTrip $trip): void
    {
        if ($trip->cost_option === FleetTrip::OPTION_CUSTOMER_VEHICLE) {
            throw new RuntimeException("{$trip->number} is in the customer's own vehicle: the company carries no cost on it.");
        }

        if (in_array($trip->status, [FleetTrip::STATUS_CLOSED, FleetTrip::STATUS_CANCELLED], true)) {
            throw new RuntimeException("{$trip->number} is {$trip->status}: nothing more can be charged to it.");
        }
    }

    private function lock(FleetTrip $trip): FleetTrip
    {
        return FleetTrip::query()->with('vehicle', 'driver')->whereKey($trip->id)->lockForUpdate()->firstOrFail();
    }

    /** @param  list<string>  $allowed */
    private function assertStatus(FleetTrip $trip, array $allowed, string $verb): void
    {
        if (! in_array($trip->status, $allowed, true)) {
            throw new RuntimeException("{$trip->number} is {$trip->status} and cannot be {$verb}.");
        }
    }

    private function num(float|string|null $value): string
    {
        return rtrim(rtrim(number_format((float) $value, 2, '.', ','), '0'), '.');
    }
}
