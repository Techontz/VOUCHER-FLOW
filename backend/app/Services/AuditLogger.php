<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;

/**
 * Append-only trail: who did what, when, from which device.
 */
class AuditLogger
{
    public function log(
        string $action,
        string $description,
        ?Model $entity = null,
        ?array $before = null,
        ?array $after = null,
        ?int $companyId = null,
        ?User $actor = null,
    ): AuditLog {
        // Sign-in is recorded before the guard holds a user, so the caller may
        // hand the actor in explicitly.
        $actor ??= auth()->user();
        $request = request();

        return AuditLog::create([
            'company_id' => $companyId ?? $entity?->company_id ?? $actor?->company_id,
            'actor_id' => $actor?->id,
            'actor_name' => $actor?->name ?? 'System',
            'actor_role' => $actor?->role,
            'action' => $action,
            'entity_type' => $entity ? class_basename($entity) : null,
            'entity_id' => $entity?->getKey(),
            'description' => mb_substr($description, 0, 500),
            'change_summary' => $this->summarise($before, $after),
            'before' => $before,
            'after' => $after,
            'ip' => $request?->ip(),
            'user_agent' => mb_substr((string) $request?->userAgent(), 0, 255),
        ]);
    }

    /** "Draft → Awaiting HOD signature", as shown in the audit log screen. */
    private function summarise(?array $before, ?array $after): ?string
    {
        if (! $before || ! $after) {
            return null;
        }

        $parts = [];

        foreach ($after as $key => $value) {
            $old = $before[$key] ?? null;

            if ($old !== $value) {
                $parts[] = sprintf('%s → %s', $this->stringify($old), $this->stringify($value));
            }
        }

        return $parts ? mb_substr(implode(' · ', $parts), 0, 255) : null;
    }

    private function stringify(mixed $value): string
    {
        return match (true) {
            $value === null => '—',
            is_bool($value) => $value ? 'yes' : 'no',
            is_array($value) => json_encode($value),
            default => (string) $value,
        };
    }
}
