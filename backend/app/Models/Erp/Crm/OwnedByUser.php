<?php

namespace App\Models\Erp\Crm;

use App\Models\User;
use App\Support\Erp\Permissions;
use Illuminate\Database\Eloquent\Builder;

/**
 * A salesperson sees the CRM records they own; crm.view_all sees everyone's.
 */
trait OwnedByUser
{
    public function scopeVisibleTo(Builder $query, User $user): Builder
    {
        if (app(Permissions::class)->allows($user, 'crm.view_all')) {
            return $query;
        }

        return $query->where($this->getTable().'.owner_id', $user->id);
    }

    public function isVisibleTo(User $user): bool
    {
        return $this->owner_id === $user->id || app(Permissions::class)->allows($user, 'crm.view_all');
    }
}
