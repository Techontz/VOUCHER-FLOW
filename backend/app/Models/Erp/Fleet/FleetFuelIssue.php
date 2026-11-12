<?php

namespace App\Models\Erp\Fleet;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Account;
use App\Models\Erp\Supplier;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Fuel put into a vehicle for a trip, with the receipt that proves it. */
class FleetFuelIssue extends Model
{
    use BelongsToTenant;

    public const PENDING = 'pending';

    public const APPROVED = 'approved';

    public const REJECTED = 'rejected';

    protected $table = 'fleet_fuel_issues';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'trip_id' => 'integer',
            'vehicle_id' => 'integer',
            'account_id' => 'integer',
            'supplier_id' => 'integer',
            'issue_date' => 'date:Y-m-d',
            'approved_at' => 'datetime',
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

    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class);
    }

    public function recorder(): BelongsTo
    {
        return $this->belongsTo(User::class, 'recorded_by');
    }

    public function approver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'approved_by');
    }
}
