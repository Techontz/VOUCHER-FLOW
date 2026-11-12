<?php

namespace App\Models\Erp\Fleet;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** A tyre by serial number: where it is fitted, from when, and when it came off. */
class FleetTyre extends Model
{
    use BelongsToTenant;

    protected $table = 'fleet_tyres';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'vehicle_id' => 'integer',
            'fitted_date' => 'date:Y-m-d',
            'removed_date' => 'date:Y-m-d',
        ];
    }

    public function vehicle(): BelongsTo
    {
        return $this->belongsTo(FleetVehicle::class, 'vehicle_id');
    }
}
