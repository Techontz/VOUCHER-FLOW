<?php

namespace App\Models\Erp\Fleet;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Customer;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One journey: a vehicle and driver from origin to destination, carrying
 * cargo for a customer or a business document, under one of the four
 * transport cost options.
 */
class FleetTrip extends Model
{
    use BelongsToTenant;

    /** The customer collects in their own vehicle: no company cost at all. */
    public const OPTION_CUSTOMER_VEHICLE = 'customer_vehicle';

    /** A company vehicle, and the customer is charged for transport. */
    public const OPTION_CHARGED = 'charged';

    /** A company vehicle, transport already in the product price: cost only. */
    public const OPTION_INCLUDED = 'included';

    /** A hired vehicle: the hire is the cost, payable to its owner. */
    public const OPTION_HIRED = 'hired';

    public const OPTIONS = [self::OPTION_CUSTOMER_VEHICLE, self::OPTION_CHARGED, self::OPTION_INCLUDED, self::OPTION_HIRED];

    public const STATUS_PLANNED = 'planned';

    public const STATUS_DISPATCHED = 'dispatched';

    public const STATUS_COMPLETED = 'completed';

    public const STATUS_CLOSED = 'closed';

    public const STATUS_CANCELLED = 'cancelled';

    public const STATUSES = [self::STATUS_PLANNED, self::STATUS_DISPATCHED, self::STATUS_COMPLETED, self::STATUS_CLOSED, self::STATUS_CANCELLED];

    protected $table = 'fleet_trips';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'vehicle_id' => 'integer',
            'driver_id' => 'integer',
            'customer_id' => 'integer',
            'source_id' => 'integer',
            'created_by' => 'integer',
            'closed_by' => 'integer',
            'variance_approved_by' => 'integer',
            'fuel_over_standard' => 'boolean',
            'planned_start' => 'datetime',
            'planned_end' => 'datetime',
            'actual_start' => 'datetime',
            'actual_end' => 'datetime',
            'dispatched_at' => 'datetime',
            'completed_at' => 'datetime',
            'closed_at' => 'datetime',
            'variance_approved_at' => 'datetime',
        ];
    }

    /** Whether the company itself runs and pays for the vehicle on this trip. */
    public function usesCompanyVehicle(): bool
    {
        return in_array($this->cost_option, [self::OPTION_CHARGED, self::OPTION_INCLUDED], true);
    }

    /** The trip's distance: from the odometer when both readings exist, else as planned. */
    public function distance(): float
    {
        if ($this->odometer_in !== null && $this->odometer_out !== null) {
            return max(0, (float) $this->odometer_in - (float) $this->odometer_out);
        }

        return (float) $this->distance_km;
    }

    public function vehicle(): BelongsTo
    {
        return $this->belongsTo(FleetVehicle::class, 'vehicle_id');
    }

    public function driver(): BelongsTo
    {
        return $this->belongsTo(FleetDriver::class, 'driver_id');
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function fuelIssues(): HasMany
    {
        return $this->hasMany(FleetFuelIssue::class, 'trip_id');
    }

    public function expenses(): HasMany
    {
        return $this->hasMany(FleetTripExpense::class, 'trip_id');
    }

    public function allocations(): HasMany
    {
        return $this->hasMany(FleetCostAllocation::class, 'trip_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function closer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'closed_by');
    }

    public function varianceApprover(): BelongsTo
    {
        return $this->belongsTo(User::class, 'variance_approved_by');
    }
}
