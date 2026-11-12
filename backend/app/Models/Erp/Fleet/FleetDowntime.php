<?php

namespace App\Models\Erp\Fleet;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** A period a vehicle could not work: in the garage, broken down or after an accident. */
class FleetDowntime extends Model
{
    use BelongsToTenant;

    public const REASONS = ['maintenance', 'breakdown', 'accident', 'other'];

    protected $table = 'fleet_downtimes';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'vehicle_id' => 'integer',
            'service_record_id' => 'integer',
            'started_at' => 'datetime',
            'ended_at' => 'datetime',
        ];
    }

    public function hours(): float
    {
        return round($this->started_at->diffInMinutes($this->ended_at ?? now()) / 60, 1);
    }

    public function vehicle(): BelongsTo
    {
        return $this->belongsTo(FleetVehicle::class, 'vehicle_id');
    }
}
