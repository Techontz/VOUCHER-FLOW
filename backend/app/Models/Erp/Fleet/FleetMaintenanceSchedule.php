<?php

namespace App\Models\Erp\Fleet;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** A service a vehicle needs every so many km, or every so many days, or both. */
class FleetMaintenanceSchedule extends Model
{
    use BelongsToTenant;

    protected $table = 'fleet_maintenance_schedules';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'vehicle_id' => 'integer',
            'interval_km' => 'integer',
            'interval_days' => 'integer',
            'is_active' => 'boolean',
            'last_done_date' => 'date:Y-m-d',
            'next_due_date' => 'date:Y-m-d',
        ];
    }

    /** Recomputes the next due point from the last time it was done. */
    public function recomputeNextDue(): void
    {
        $this->next_due_odometer = $this->interval_km && $this->last_done_odometer !== null
            ? (float) $this->last_done_odometer + $this->interval_km : null;
        $this->next_due_date = $this->interval_days && $this->last_done_date
            ? $this->last_done_date->copy()->addDays($this->interval_days) : null;
    }

    /**
     * overdue, due (within 14 days or 1,000 km) or ok, for the vehicle's odometer.
     */
    public function dueState(float $odometer): string
    {
        $overdue = ($this->next_due_odometer !== null && $odometer >= (float) $this->next_due_odometer)
            || ($this->next_due_date && $this->next_due_date->lt(today()));

        if ($overdue) {
            return 'overdue';
        }

        $soon = ($this->next_due_odometer !== null && $odometer >= (float) $this->next_due_odometer - 1000)
            || ($this->next_due_date && $this->next_due_date->lte(today()->addDays(14)));

        return $soon ? 'due' : 'ok';
    }

    public function vehicle(): BelongsTo
    {
        return $this->belongsTo(FleetVehicle::class, 'vehicle_id');
    }
}
