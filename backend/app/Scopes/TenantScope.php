<?php

namespace App\Scopes;

use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

/**
 * Constrains every query on a tenant-owned model to the resolved company.
 *
 * Fails closed on purpose: with no tenant resolved and no platform flag the
 * scope matches nothing, so a missing middleware leaks no data.
 */
class TenantScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        $tenant = app(TenantContext::class);

        if ($tenant->isPlatform()) {
            return;
        }

        $column = $model->getTable().'.'.$model->tenantColumn();

        if (! $tenant->hasTenant()) {
            $builder->whereRaw('1 = 0');

            return;
        }

        $builder->where($column, $tenant->id());
    }
}
