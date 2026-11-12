<?php

namespace App\Models\Erp\Hr;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/**
 * The base of every HR table: tenant-scoped, mass-assignable except its key.
 * Integer keys are cast because they are compared with === in PHP.
 */
abstract class HrModel extends Model
{
    use BelongsToTenant;

    protected $guarded = ['id'];

    /** @var array<string, string> casts every HR model shares */
    protected const BASE_CASTS = ['company_id' => 'integer'];

    /** @return array<string, string> */
    protected function hrCasts(): array
    {
        return [];
    }

    protected function casts(): array
    {
        return [...self::BASE_CASTS, ...$this->hrCasts()];
    }
}
