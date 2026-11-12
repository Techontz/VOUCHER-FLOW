<?php

namespace App\Http\Controllers\Api\Erp\Crm;

use App\Support\Erp\Permissions;
use Illuminate\Http\Request;
use RuntimeException;

/**
 * A salesperson always owns what they create; only crm.assign hands a CRM
 * record to someone else.
 */
trait AssignsOwner
{
    private function ownerFor(Request $request, ?int $requested, ?int $current = null): int
    {
        $user = $request->user();
        $requested ??= $current ?? $user->id;

        if ($requested !== ($current ?? $user->id) && ! app(Permissions::class)->allows($user, 'crm.assign')) {
            throw new RuntimeException('Only someone who may assign CRM records can give this to another person.');
        }

        return $requested;
    }
}
