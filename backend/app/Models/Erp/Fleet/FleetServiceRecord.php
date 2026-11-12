<?php

namespace App\Models\Erp\Fleet;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Account;
use App\Models\Erp\Supplier;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Work done on a vehicle, and what it cost. Posted to the ledger once. */
class FleetServiceRecord extends Model
{
    use BelongsToTenant;

    public const DRAFT = 'draft';

    public const POSTED = 'posted';

    public const CANCELLED = 'cancelled';

    protected $table = 'fleet_service_records';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'vehicle_id' => 'integer',
            'schedule_id' => 'integer',
            'supplier_id' => 'integer',
            'account_id' => 'integer',
            'service_date' => 'date:Y-m-d',
            'posted_at' => 'datetime',
        ];
    }

    public function vehicle(): BelongsTo
    {
        return $this->belongsTo(FleetVehicle::class, 'vehicle_id');
    }

    public function schedule(): BelongsTo
    {
        return $this->belongsTo(FleetMaintenanceSchedule::class, 'schedule_id');
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class);
    }

    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function poster(): BelongsTo
    {
        return $this->belongsTo(User::class, 'posted_by');
    }
}
