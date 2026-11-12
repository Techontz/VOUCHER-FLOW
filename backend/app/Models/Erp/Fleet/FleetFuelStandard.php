<?php

namespace App\Models\Erp\Fleet;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * How much fuel a vehicle, a route, or a vehicle on a route should take:
 * litres per 100 km, or litres per trip.
 */
class FleetFuelStandard extends Model
{
    use BelongsToTenant;

    public const PER_100KM = 'per_100km';

    public const PER_TRIP = 'per_trip';

    protected $table = 'fleet_fuel_standards';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'vehicle_id' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    /** Litres this standard allows for a trip of the given distance. */
    public function litresFor(float $distanceKm): float
    {
        return round($this->basis === self::PER_TRIP ? (float) $this->litres : (float) $this->litres * $distanceKm / 100, 3);
    }

    public function vehicle(): BelongsTo
    {
        return $this->belongsTo(FleetVehicle::class, 'vehicle_id');
    }
}
