<?php

namespace App\Models\Erp\Fleet;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Supplier;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

/** A truck, van or pickup the company runs, its own or hired from an owner. */
class FleetVehicle extends Model
{
    use BelongsToTenant;

    public const OWNED = 'owned';

    public const HIRED = 'hired';

    public const STATUS_AVAILABLE = 'available';

    public const STATUS_ON_TRIP = 'on_trip';

    public const STATUS_MAINTENANCE = 'maintenance';

    public const STATUS_OUT_OF_SERVICE = 'out_of_service';

    public const STATUSES = [self::STATUS_AVAILABLE, self::STATUS_ON_TRIP, self::STATUS_MAINTENANCE, self::STATUS_OUT_OF_SERVICE];

    public const TYPES = ['truck', 'trailer', 'tanker', 'van', 'pickup', 'car', 'motorcycle', 'other'];

    public const HIRE_BASES = ['per_trip', 'per_km', 'per_day'];

    protected $table = 'fleet_vehicles';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'supplier_id' => 'integer',
            'year' => 'integer',
            'hire_includes_fuel' => 'boolean',
            'is_active' => 'boolean',
            'insurance_expiry' => 'date:Y-m-d',
            'road_licence_expiry' => 'date:Y-m-d',
        ];
    }

    public function isHired(): bool
    {
        return $this->ownership === self::HIRED;
    }

    /** What one month of this vehicle costs whether it moves or not. */
    public function monthlyFixedCost(): float
    {
        return round((float) $this->monthly_insurance + (float) $this->monthly_licence
            + (float) $this->monthly_depreciation + (float) $this->monthly_other_fixed, 2);
    }

    public function label(): string
    {
        return trim("{$this->registration_number} {$this->make} {$this->model}");
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class);
    }

    public function driver(): HasOne
    {
        return $this->hasOne(FleetDriver::class, 'vehicle_id');
    }

    public function trips(): HasMany
    {
        return $this->hasMany(FleetTrip::class, 'vehicle_id');
    }

    public function schedules(): HasMany
    {
        return $this->hasMany(FleetMaintenanceSchedule::class, 'vehicle_id');
    }

    public function services(): HasMany
    {
        return $this->hasMany(FleetServiceRecord::class, 'vehicle_id');
    }

    public function tyres(): HasMany
    {
        return $this->hasMany(FleetTyre::class, 'vehicle_id');
    }

    public function downtimes(): HasMany
    {
        return $this->hasMany(FleetDowntime::class, 'vehicle_id');
    }
}
