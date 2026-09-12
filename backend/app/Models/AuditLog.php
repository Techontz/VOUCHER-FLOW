<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Append-only record of every state change. Not tenant-scoped at the model level
 * because the platform super admin reads across companies; controllers scope it
 * explicitly via forCompany().
 */
class AuditLog extends Model
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
            'company_id' => 'integer',
            'actor_id' => 'integer',
            'entity_id' => 'integer',
            'before' => 'array',
            'after' => 'array',
        ];
    }

    public function actor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'actor_id');
    }

    public function company(): BelongsTo
    {
        return $this->belongsTo(Company::class);
    }

    public function scopeForCompany($query, ?int $companyId)
    {
        return $companyId ? $query->where('company_id', $companyId) : $query;
    }
}
