<?php

namespace App\Models\Erp\Fleet;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** The share of one month of a vehicle's fixed costs that one trip absorbed. */
class FleetCostAllocation extends Model
{
    use BelongsToTenant;

    protected $table = 'fleet_cost_allocations';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'vehicle_id' => 'integer',
            'trip_id' => 'integer',
        ];
    }

    public function trip(): BelongsTo
    {
        return $this->belongsTo(FleetTrip::class, 'trip_id');
    }

    public function vehicle(): BelongsTo
    {
        return $this->belongsTo(FleetVehicle::class, 'vehicle_id');
    }
}
