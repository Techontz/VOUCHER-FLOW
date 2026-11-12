<?php

namespace App\Services\Erp\Procurement;

use App\Models\Erp\Procurement\ProcurementApproval;
use App\Models\Erp\Procurement\ProcurementSetting;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use RuntimeException;

/**
 * Approval by amount, shared by requisitions and purchase orders.
 *
 * Up to the company's threshold one approval is enough. Above it, two are
 * needed from two different people, and the second must come from a senior
 * role (finance, director or CEO unless the company says otherwise). Nobody
 * approves what they raised themselves. Every decision is a row of its own,
 * with who, when and why.
 */
class Approvals
{
    public function required(float $total): int
    {
        return $total > (float) ProcurementSetting::current()->approval_threshold ? 2 : 1;
    }

    public function isSenior(User $user): bool
    {
        return $user->isCompanyAdmin() || in_array($user->role, ProcurementSetting::current()->seniorRoles(), true);
    }

    /**
     * Records an approval and says whether the document is now fully approved.
     */
    public function approve(Model $document, int $required, int $raisedBy, User $actor, ?string $comment): bool
    {
        $label = $document->getAttribute('number');

        if ($raisedBy === $actor->id) {
            throw new RuntimeException("You raised {$label}, so someone else must approve it.");
        }

        $current = $this->currentRound($document);

        if ($current->contains('user_id', $actor->id)) {
            throw new RuntimeException("You have already approved {$label}; a second approval must come from someone else.");
        }

        $level = $current->count() + 1;

        if ($required > 1 && $level === $required && ! $this->isSenior($actor)) {
            $threshold = number_format((float) ProcurementSetting::current()->approval_threshold);

            throw new RuntimeException("{$label} is above the approval threshold of {$threshold}: the final approval must come from a senior approver (finance, director or CEO).");
        }

        $this->record($document, $level, ProcurementApproval::APPROVED, $actor, $comment);

        return $level >= $required;
    }

    public function reject(Model $document, User $actor, string $comment): void
    {
        $this->record($document, $this->currentRound($document)->count() + 1, ProcurementApproval::REJECTED, $actor, $comment);
    }

    /** Approvals given since the last rejection: a rejected document starts again. */
    public function currentRound(Model $document)
    {
        $all = ProcurementApproval::query()
            ->where('approvable_type', class_basename($document))
            ->where('approvable_id', $document->getKey())
            ->orderBy('id')
            ->get();

        $lastRejection = $all->where('decision', ProcurementApproval::REJECTED)->max('id') ?? 0;

        return $all->filter(fn ($a) => $a->id > $lastRejection && $a->decision === ProcurementApproval::APPROVED)->values();
    }

    private function record(Model $document, int $level, string $decision, User $actor, ?string $comment): void
    {
        ProcurementApproval::create([
            'approvable_type' => class_basename($document),
            'approvable_id' => $document->getKey(),
            'level' => $level,
            'decision' => $decision,
            'user_id' => $actor->id,
            'comment' => $comment !== null ? mb_substr($comment, 0, 500) : null,
        ]);
    }
}
