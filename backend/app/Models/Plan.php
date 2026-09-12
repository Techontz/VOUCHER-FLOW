<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Plan extends Model
{
    use HasFactory;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            /*
             * Integer columns are cast because they are compared with === in
             * PHP. MySQL returns them as strings under emulated prepared
             * statements, where "8" === 8 is false — which silently turned an
             * owner into a stranger and a matching id into a mismatch.
             */
            'max_users' => 'integer',
            'max_vouchers_per_month' => 'integer',
            'max_departments' => 'integer',
            'max_approval_levels' => 'integer',
            'storage_mb' => 'integer',
            'trial_days' => 'integer',
            'sort_order' => 'integer',
            'price' => 'decimal:2',
            'features' => 'array',
            'is_active' => 'boolean',
            'is_public' => 'boolean',
        ];
    }

    public function companies(): HasMany
    {
        return $this->hasMany(Company::class);
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(Subscription::class);
    }

    public function isUnlimited(string $limit): bool
    {
        return $this->{$limit} === null;
    }
}
