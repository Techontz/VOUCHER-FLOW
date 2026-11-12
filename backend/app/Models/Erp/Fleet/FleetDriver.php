<?php

namespace App\Models\Erp\Fleet;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A person who drives for the company: their user account plus their licence. */
class FleetDriver extends Model
{
    use BelongsToTenant;

    protected $table = 'fleet_drivers';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'user_id' => 'integer',
            'vehicle_id' => 'integer',
            'is_active' => 'boolean',
            'licence_expiry' => 'date:Y-m-d',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function vehicle(): BelongsTo
    {
        return $this->belongsTo(FleetVehicle::class, 'vehicle_id');
    }

    public function trips(): HasMany
    {
        return $this->hasMany(FleetTrip::class, 'driver_id');
    }
}
