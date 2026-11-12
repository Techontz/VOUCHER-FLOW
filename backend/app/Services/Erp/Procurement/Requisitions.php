<?php

namespace App\Services\Erp\Procurement;

use App\Models\Erp\Procurement\PurchaseRequisition;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Purchase requisitions: drafted by a department, submitted, approved by the
 * amount rules in Approvals, and finally turned into a purchase order.
 */
class Requisitions
{
    public const RELATIONS = [
        'lines.product:id,sku,name,unit_id', 'lines.product.unit:id,code', 'lines.expenseAccount:id,code,name',
        'department:id,name', 'requester:id,name', 'approvals.user:id,name,role', 'orders:id,number,status,purchase_requisition_id',
    ];

    public function __construct(
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly Approvals $approvals,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function create(array $data, User $actor): PurchaseRequisition
    {
        return DB::transaction(function () use ($data, $actor) {
            $requisition = PurchaseRequisition::create([
                ...$this->header($data, $actor),
                'number' => $this->numbers->next('PRQ'),
                'requested_by' => $actor->id,
                'status' => PurchaseRequisition::STATUS_DRAFT,
            ]);

            $this->writeLines($requisition, $data['lines'] ?? []);
            $this->audit->log('procurement.requisition.created', "Raised requisition {$requisition->number}", $requisition, actor: $actor);

            return $requisition->fresh(self::RELATIONS);
        });
    }

    /** @param  array<string, mixed>  $data */
    public function update(PurchaseRequisition $requisition, array $data, User $actor): PurchaseRequisition
    {
        return DB::transaction(function () use ($requisition, $data, $actor) {
            $locked = $this->lock($requisition);
            $this->assertStatus($locked, [PurchaseRequisition::STATUS_DRAFT], 'edited');
            $this->assertOwner($locked, $actor);

            $locked->update($this->header($data, $actor));
            $locked->lines()->delete();
            $this->writeLines($locked, $data['lines'] ?? []);
            $this->audit->log('procurement.requisition.updated', "Edited requisition {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function submit(PurchaseRequisition $requisition, User $actor): PurchaseRequisition
    {
        return DB::transaction(function () use ($requisition, $actor) {
            $locked = $this->lock($requisition);
            $this->assertStatus($locked, [PurchaseRequisition::STATUS_DRAFT], 'submitted');
            $this->assertOwner($locked, $actor);

            $locked->update([
                'status' => PurchaseRequisition::STATUS_SUBMITTED,
                'submitted_at' => now(),
                // Fixed at submission, so a later change of threshold does not move the goalposts mid-approval.
                'approvals_required' => $this->approvals->required((float) $locked->total),
            ]);
            $this->audit->log('procurement.requisition.submitted', "Submitted requisition {$locked->number} for approval", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function approve(PurchaseRequisition $requisition, User $actor, ?string $comment): PurchaseRequisition
    {
        return DB::transaction(function () use ($requisition, $actor, $comment) {
            $locked = $this->lock($requisition);
            $this->assertStatus($locked, [PurchaseRequisition::STATUS_SUBMITTED], 'approved');

            $done = $this->approvals->approve($locked, $locked->approvals_required, $locked->requested_by, $actor, $comment);

            if ($done) {
                $locked->update(['status' => PurchaseRequisition::STATUS_APPROVED, 'approved_at' => now()]);
            }

            $this->audit->log('procurement.requisition.approved', $done
                ? "Approved requisition {$locked->number}"
                : "Gave the first of two approvals to requisition {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function reject(PurchaseRequisition $requisition, User $actor, string $comment): PurchaseRequisition
    {
        return DB::transaction(function () use ($requisition, $actor, $comment) {
            $locked = $this->lock($requisition);
            $this->assertStatus($locked, [PurchaseRequisition::STATUS_SUBMITTED], 'rejected');

            if ($locked->requested_by === $actor->id) {
                throw new RuntimeException("You raised {$locked->number}; cancel it instead of rejecting it.");
            }

            $this->approvals->reject($locked, $actor, $comment);
            $locked->update(['status' => PurchaseRequisition::STATUS_REJECTED, 'rejected_at' => now()]);
            $this->audit->log('procurement.requisition.rejected', "Rejected requisition {$locked->number} · {$comment}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function cancel(PurchaseRequisition $requisition, User $actor): PurchaseRequisition
    {
        return DB::transaction(function () use ($requisition, $actor) {
            $locked = $this->lock($requisition);
            $this->assertStatus($locked, [PurchaseRequisition::STATUS_DRAFT, PurchaseRequisition::STATUS_SUBMITTED, PurchaseRequisition::STATUS_APPROVED], 'cancelled');
            $this->assertOwner($locked, $actor);

            $locked->update(['status' => PurchaseRequisition::STATUS_CANCELLED, 'cancelled_at' => now()]);
            $this->audit->log('procurement.requisition.cancelled', "Cancelled requisition {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    /** Called when an order is raised from the requisition. */
    public function markOrdered(PurchaseRequisition $requisition, User $actor): void
    {
        $locked = $this->lock($requisition);

        if (! in_array($locked->status, [PurchaseRequisition::STATUS_APPROVED, PurchaseRequisition::STATUS_ORDERED], true)) {
            throw new RuntimeException("Requisition {$locked->number} is {$locked->status}; only an approved requisition can be ordered.");
        }

        if ($locked->status === PurchaseRequisition::STATUS_APPROVED) {
            $locked->update(['status' => PurchaseRequisition::STATUS_ORDERED]);
            $this->audit->log('procurement.requisition.ordered', "Requisition {$locked->number} ordered", $locked, actor: $actor);
        }
    }

    /** @return array<string, mixed> */
    private function header(array $data, User $actor): array
    {
        return [
            'department_id' => $data['department_id'] ?? $actor->department_id,
            'needed_by' => $data['needed_by'] ?? null,
            'justification' => $data['justification'],
        ];
    }

    /** @param  list<array<string, mixed>>  $lines */
    private function writeLines(PurchaseRequisition $requisition, array $lines): void
    {
        if (! $lines) {
            throw new RuntimeException('Add at least one line.');
        }

        $total = 0.0;

        foreach (array_values($lines) as $i => $line) {
            $quantity = (float) ($line['quantity'] ?? 0);

            if ($quantity <= 0) {
                throw new RuntimeException('Line '.($i + 1).': the quantity must be greater than zero.');
            }

            $price = (float) ($line['estimated_unit_price'] ?? 0);
            $amount = Lines::money($quantity * $price);
            $total += $amount;

            $requisition->lines()->create([
                ...Lines::normalise($line, $i),
                'quantity' => $quantity,
                'estimated_unit_price' => $price,
                'amount' => $amount,
            ]);
        }

        $requisition->update(['total' => Lines::money($total)]);
    }

    private function lock(PurchaseRequisition $requisition): PurchaseRequisition
    {
        return PurchaseRequisition::query()->whereKey($requisition->id)->lockForUpdate()->firstOrFail();
    }

    /** @param  list<string>  $allowed */
    private function assertStatus(PurchaseRequisition $requisition, array $allowed, string $verb): void
    {
        if (! in_array($requisition->status, $allowed, true)) {
            throw new RuntimeException("Requisition {$requisition->number} is {$requisition->status} and cannot be {$verb}.");
        }
    }

    private function assertOwner(PurchaseRequisition $requisition, User $actor): void
    {
        if ($requisition->requested_by !== $actor->id && ! $actor->isCompanyAdmin()) {
            throw new RuntimeException("Only the person who raised {$requisition->number} can change it.");
        }
    }
}
