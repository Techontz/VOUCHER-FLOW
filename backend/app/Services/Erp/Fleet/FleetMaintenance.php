<?php

namespace App\Services\Erp\Fleet;

use App\Models\Erp\Fleet\FleetDowntime;
use App\Models\Erp\Fleet\FleetMaintenanceSchedule;
use App\Models\Erp\Fleet\FleetServiceRecord;
use App\Models\Erp\Fleet\FleetTyre;
use App\Models\Erp\Fleet\FleetVehicle;
use App\Models\Erp\Supplier;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Service records, tyres and downtime.
 *
 * A service record is a draft until posted. Posting, once, under the row
 * lock: Dr Vehicle repairs & maintenance / Cr the garage on Accounts payable,
 * or the cash or bank account it was paid from; the schedule it satisfies
 * moves its next due point on, and the vehicle's odometer catches up.
 */
class FleetMaintenance
{
    public function __construct(
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function createService(array $data, User $actor): FleetServiceRecord
    {
        return DB::transaction(function () use ($data, $actor) {
            $record = FleetServiceRecord::create([
                ...$this->serviceAttributes($data),
                'number' => $this->numbers->next('SRV'),
                'status' => FleetServiceRecord::DRAFT,
                'created_by' => $actor->id,
            ]);

            $this->audit->log('fleet.service.created', "Recorded service {$record->number}", $record, actor: $actor);

            return $record;
        });
    }

    /** @param  array<string, mixed>  $data */
    public function updateService(FleetServiceRecord $record, array $data, User $actor): FleetServiceRecord
    {
        return DB::transaction(function () use ($record, $data, $actor) {
            $locked = $this->lockService($record);
            $this->assertDraft($locked, 'edited');
            $locked->update($this->serviceAttributes($data));
            $this->audit->log('fleet.service.updated', "Edited draft service {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    public function postService(FleetServiceRecord $record, User $actor): FleetServiceRecord
    {
        return DB::transaction(function () use ($record, $actor) {
            $locked = $this->lockService($record);
            $this->assertDraft($locked, 'posted');

            $locked->update(['status' => FleetServiceRecord::POSTED, 'posted_by' => $actor->id, 'posted_at' => now()]);

            if ($locked->schedule_id) {
                $schedule = FleetMaintenanceSchedule::query()->whereKey($locked->schedule_id)->lockForUpdate()->first();
                if ($schedule) {
                    $schedule->last_done_date = $locked->service_date;
                    $schedule->last_done_odometer = $locked->odometer ?? $schedule->last_done_odometer;
                    $schedule->recomputeNextDue();
                    $schedule->save();
                }
            }

            if ($locked->odometer !== null) {
                FleetVehicle::query()->whereKey($locked->vehicle_id)->where('odometer', '<', $locked->odometer)->update(['odometer' => $locked->odometer]);
            }

            $cost = round((float) $locked->cost, 2);

            if ($cost > 0 && BusinessConfig::of($this->tenant->company())->postsToLedger()) {
                $vehicle = FleetVehicle::query()->find($locked->vehicle_id);
                $garage = $locked->supplier_id ? Supplier::query()->whereKey($locked->supplier_id)->value('name') : null;
                $credit = $locked->account_id
                    ? ['account_id' => $locked->account_id, 'credit' => $cost, 'description' => $locked->number]
                    : ['account' => 'payable', 'credit' => $cost, 'description' => trim("{$locked->number} {$garage}")];

                $this->journal->post([
                    ['account' => 'vehicle_maintenance', 'debit' => $cost, 'description' => "{$locked->number} {$vehicle?->registration_number}"],
                    $credit,
                ], "Maintenance {$locked->number}, {$vehicle?->registration_number}", $locked->service_date->toDateString(), $locked, 'post', $actor);
            }

            $this->audit->log('fleet.service.posted', "Posted service {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    public function cancelService(FleetServiceRecord $record, User $actor): FleetServiceRecord
    {
        return DB::transaction(function () use ($record, $actor) {
            $locked = $this->lockService($record);
            $this->assertDraft($locked, 'cancelled');
            $locked->update(['status' => FleetServiceRecord::CANCELLED]);
            $this->audit->log('fleet.service.cancelled', "Cancelled draft service {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    /* ------------------------------------------------------------ tyres */

    /** @param  array<string, mixed>  $data */
    public function fitTyre(array $data, User $actor): FleetTyre
    {
        return DB::transaction(function () use ($data, $actor) {
            $vehicle = FleetVehicle::query()->whereKey($data['vehicle_id'])->lockForUpdate()->firstOrFail();

            $occupied = FleetTyre::query()->where('vehicle_id', $vehicle->id)
                ->where('position', $data['position'])->whereNull('removed_date')->first();

            if ($occupied) {
                throw new RuntimeException("Tyre {$occupied->serial_number} is still fitted at {$data['position']} on {$vehicle->registration_number}. Remove it first.");
            }

            if (FleetTyre::query()->where('serial_number', $data['serial_number'])->whereNull('removed_date')->exists()) {
                throw new RuntimeException("Tyre {$data['serial_number']} is already fitted to a vehicle.");
            }

            $tyre = FleetTyre::create([
                'vehicle_id' => $vehicle->id,
                'position' => $data['position'],
                'serial_number' => $data['serial_number'],
                'brand' => $data['brand'] ?? null,
                'size' => $data['size'] ?? null,
                'cost' => $data['cost'] ?? 0,
                'fitted_date' => $data['fitted_date'] ?? today()->toDateString(),
                'fitted_odometer' => $data['fitted_odometer'] ?? $vehicle->odometer,
                'created_by' => $actor->id,
            ]);

            $this->audit->log('fleet.tyre.fitted', "Fitted tyre {$tyre->serial_number} at {$tyre->position} on {$vehicle->registration_number}", $tyre, actor: $actor);

            return $tyre;
        });
    }

    /** @param  array<string, mixed>  $data */
    public function removeTyre(FleetTyre $tyre, array $data, User $actor): FleetTyre
    {
        return DB::transaction(function () use ($tyre, $data, $actor) {
            $locked = FleetTyre::query()->whereKey($tyre->id)->lockForUpdate()->firstOrFail();

            if ($locked->removed_date) {
                throw new RuntimeException("Tyre {$locked->serial_number} was already removed.");
            }

            $odometer = (float) ($data['removed_odometer'] ?? $locked->vehicle?->odometer);

            if ($odometer < (float) $locked->fitted_odometer) {
                throw new RuntimeException('The odometer at removal cannot be below the odometer when it was fitted.');
            }

            $locked->update([
                'removed_date' => $data['removed_date'] ?? today()->toDateString(),
                'removed_odometer' => $odometer,
                'removal_reason' => $data['removal_reason'] ?? null,
            ]);

            $this->audit->log('fleet.tyre.removed', "Removed tyre {$locked->serial_number}", $locked, actor: $actor);

            return $locked;
        });
    }

    /* ------------------------------------------------------------ downtime */

    /** @param  array<string, mixed>  $data */
    public function startDowntime(array $data, User $actor): FleetDowntime
    {
        return DB::transaction(function () use ($data, $actor) {
            $vehicle = FleetVehicle::query()->whereKey($data['vehicle_id'])->lockForUpdate()->firstOrFail();

            if ($vehicle->status === FleetVehicle::STATUS_ON_TRIP) {
                throw new RuntimeException("{$vehicle->registration_number} is on a trip. Complete the trip first.");
            }

            if (FleetDowntime::query()->where('vehicle_id', $vehicle->id)->whereNull('ended_at')->exists()) {
                throw new RuntimeException("{$vehicle->registration_number} is already off the road.");
            }

            $downtime = FleetDowntime::create([
                'vehicle_id' => $vehicle->id,
                'service_record_id' => $data['service_record_id'] ?? null,
                'reason' => $data['reason'],
                'description' => $data['description'] ?? null,
                'started_at' => $data['started_at'] ?? now(),
                'created_by' => $actor->id,
            ]);

            $vehicle->update(['status' => $data['reason'] === 'maintenance' ? FleetVehicle::STATUS_MAINTENANCE : FleetVehicle::STATUS_OUT_OF_SERVICE]);
            $this->audit->log('fleet.downtime.started', "{$vehicle->registration_number} off the road: {$data['reason']}", $downtime, actor: $actor);

            return $downtime;
        });
    }

    public function endDowntime(FleetDowntime $downtime, ?string $at, User $actor): FleetDowntime
    {
        return DB::transaction(function () use ($downtime, $at, $actor) {
            $locked = FleetDowntime::query()->whereKey($downtime->id)->lockForUpdate()->firstOrFail();

            if ($locked->ended_at) {
                throw new RuntimeException('This downtime has already ended.');
            }

            $end = $at ? now()->parse($at) : now();

            if ($end->lt($locked->started_at)) {
                throw new RuntimeException('Downtime cannot end before it started.');
            }

            $locked->update(['ended_at' => $end]);
            FleetVehicle::query()->whereKey($locked->vehicle_id)
                ->whereIn('status', [FleetVehicle::STATUS_MAINTENANCE, FleetVehicle::STATUS_OUT_OF_SERVICE])
                ->update(['status' => FleetVehicle::STATUS_AVAILABLE]);

            $this->audit->log('fleet.downtime.ended', 'Vehicle back on the road', $locked, actor: $actor);

            return $locked;
        });
    }

    /* ------------------------------------------------------------ rules */

    /**
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    private function serviceAttributes(array $data): array
    {
        $cost = round((float) ($data['cost'] ?? 0), 2);
        $source = ['account_id' => null, 'supplier_id' => $data['supplier_id'] ?? null];

        if ($cost > 0) {
            $source = PaymentSource::resolve($data);
        }

        if (! empty($data['schedule_id'])) {
            $belongs = FleetMaintenanceSchedule::query()->whereKey($data['schedule_id'])->where('vehicle_id', $data['vehicle_id'])->exists();
            if (! $belongs) {
                throw new RuntimeException('That schedule belongs to another vehicle.');
            }
        }

        return [
            ...$source,
            'vehicle_id' => $data['vehicle_id'],
            'schedule_id' => $data['schedule_id'] ?? null,
            'service_date' => $data['service_date'],
            'odometer' => $data['odometer'] ?? null,
            'work_done' => $data['work_done'],
            'cost' => $cost,
            'invoice_number' => $data['invoice_number'] ?? null,
        ];
    }

    private function lockService(FleetServiceRecord $record): FleetServiceRecord
    {
        return FleetServiceRecord::query()->whereKey($record->id)->lockForUpdate()->firstOrFail();
    }

    private function assertDraft(FleetServiceRecord $record, string $verb): void
    {
        if ($record->status !== FleetServiceRecord::DRAFT) {
            throw new RuntimeException("{$record->number} is {$record->status} and cannot be {$verb}.");
        }
    }
}
