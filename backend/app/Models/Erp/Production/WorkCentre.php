<?php

namespace App\Models\Erp\Production;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A line or machine a bill of materials runs on, with its hourly cost. */
class WorkCentre extends Model
{
    use BelongsToTenant;

    protected $table = 'production_work_centres';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'capacity_per_hour' => 'decimal:3',
            'hourly_cost' => 'decimal:2',
            'is_active' => 'boolean',
        ];
    }

    public function boms(): HasMany
    {
        return $this->hasMany(Bom::class, 'work_centre_id');
    }
}
