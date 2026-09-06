<?php

namespace App\Models\Concerns;

use App\Models\Company;
use App\Scopes\TenantScope;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Applied to every model that stores tenant data. Adds the global tenant scope
 * and stamps company_id on create, so a controller cannot forget either one.
 */
trait BelongsToTenant
{
    public static function bootBelongsToTenant(): void
    {
        static::addGlobalScope(new TenantScope);

        static::creating(function ($model) {
            $column = $model->tenantColumn();

            if (! $model->getAttribute($column)) {
                $tenant = app(TenantContext::class);

                if ($tenant->hasTenant()) {
                    $model->setAttribute($column, $tenant->id());
                }
            }
        });
    }

    public function tenantColumn(): string
    {
        return 'company_id';
    }

    public function company(): BelongsTo
    {
        return $this->belongsTo(Company::class);
    }

    /** Escape hatch for platform-level queries. Use deliberately. */
    public function scopeAcrossTenants($query)
    {
        return $query->withoutGlobalScope(TenantScope::class);
    }
}
