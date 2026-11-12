<?php

namespace App\Services\Erp\Documents;

use App\Models\Company;
use App\Models\Erp\Documents\Document;
use App\Models\User;
use App\Services\Notifier;
use App\Support\Erp\BusinessConfig;
use App\Support\Erp\Permissions;
use App\Support\TenantContext;

/**
 * Tells the people responsible when a licence, permit, certificate or policy
 * is about to lapse: the document's owner and every documents manager, at 30,
 * 14, 7 and 1 days before and on the day. Run daily, each milestone fires once.
 */
class ExpiryAlerts
{
    public const MILESTONES = [30, 14, 7, 1, 0];

    public function __construct(
        private readonly TenantContext $tenant,
        private readonly Notifier $notifier,
        private readonly Permissions $permissions,
    ) {}

    public function run(): int
    {
        $sent = 0;

        foreach (Company::query()->get() as $company) {
            if (! BusinessConfig::of($company)->hasModule('documents')) {
                continue;
            }

            $sent += $this->tenant->forCompany($company, fn () => $this->forCompany($company));
        }

        return $sent;
    }

    private function forCompany(Company $company): int
    {
        $dates = array_map(fn (int $days) => today()->addDays($days)->toDateString(), self::MILESTONES);
        $documents = Document::query()->whereIn('expires_on', $dates)->get();

        if ($documents->isEmpty()) {
            return 0;
        }

        $managers = User::query()->where('company_id', $company->id)->where('status', 'active')->get()
            ->filter(fn (User $user) => $this->permissions->allows($user, 'documents.manage'));
        $sent = 0;

        foreach ($documents as $document) {
            $days = (int) today()->diffInDays($document->expires_on, false);
            [$title, $titleSw] = $days === 0
                ? ["{$document->title} expires today", "{$document->title} inaisha muda leo"]
                : ["{$document->title} expires in {$days} day(s)", "{$document->title} inaisha muda baada ya siku {$days}"];

            $people = $managers->keyBy('id');
            if ($document->owner_id && ($owner = User::query()->find($document->owner_id))) {
                $people->put($owner->id, $owner);
            }

            foreach ($people as $user) {
                $this->notifier->toUser($user, 'document_expiring', $title, $titleSw,
                    'Renew it and upload the new copy as a new version.', 'Ihuishe na upakie nakala mpya kama toleo jipya.',
                    $document, 'ph-hourglass-medium', "/erp/files/{$document->id}");
                $sent++;
            }
        }

        return $sent;
    }
}
