<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Department extends Model
{
    use BelongsToTenant, HasFactory;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',

            /*
             * Integer columns are cast because they are compared with === in
             * PHP. MySQL returns them as strings under emulated prepared
             * statements, where "8" === 8 is false — which silently turned an
             * owner into a stranger and a matching id into a mismatch.
             */
            'company_id' => 'integer',
            'hod_user_id' => 'integer',
            'manager_user_id' => 'integer',
        ];
    }


    public function hod(): BelongsTo
    {
        return $this->belongsTo(User::class, 'hod_user_id');
    }

    public function manager(): BelongsTo
    {
        return $this->belongsTo(User::class, 'manager_user_id');
    }

    public function users(): HasMany
    {
        return $this->hasMany(User::class);
    }

    public function vouchers(): HasMany
    {
        return $this->hasMany(Voucher::class);
    }
}
