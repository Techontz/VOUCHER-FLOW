<?php

namespace App\Models\Erp;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/** A tenant's own definition of a role: a built-in role re-scoped, or one it invented. */
class CompanyRole extends Model
{
    use BelongsToTenant;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'permissions' => 'array',
            'is_system' => 'boolean',
        ];
    }
}
