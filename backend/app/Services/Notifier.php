<?php

namespace App\Services;

use App\Models\AppNotification;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;

/**
 * In-app notifications. Both language variants are stored at write time so a user
 * who switches language later still reads their history in that language.
 */
class Notifier
{
    public function toUser(
        ?User $user,
        string $type,
        string $title,
        ?string $titleSw = null,
        ?string $body = null,
        ?string $bodySw = null,
        ?Model $entity = null,
        ?string $icon = null,
        ?string $actionUrl = null,
    ): ?AppNotification {
        if (! $user) {
            return null;
        }

        return AppNotification::create([
            'company_id' => $user->company_id,
            'user_id' => $user->id,
            'type' => $type,
            'icon' => $icon,
            'title' => $title,
            'title_sw' => $titleSw,
            'body' => $body,
            'body_sw' => $bodySw,
            'entity_type' => $entity ? class_basename($entity) : null,
            'entity_id' => $entity?->getKey(),
            'action_url' => $actionUrl ?? ($entity && class_basename($entity) === 'Voucher' ? "/vouchers/{$entity->getKey()}" : null),
        ]);
    }

    /** @param  iterable<User>  $users */
    public function toMany(iterable $users, string $type, string $title, ?string $titleSw = null, ?string $body = null, ?string $bodySw = null, ?Model $entity = null, ?string $icon = null): void
    {
        foreach ($users as $user) {
            $this->toUser($user, $type, $title, $titleSw, $body, $bodySw, $entity, $icon);
        }
    }
}
