<?php

namespace App\Services\Erp\Procurement;

use App\Models\Erp\Procurement\PurchaseRequisition;
use App\Models\Erp\Procurement\PurchaseRfq;
use App\Models\Erp\Procurement\SupplierQuotation;
use App\Models\Erp\Supplier;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Requests for quotation: the same lines sent to several suppliers, their
 * priced answers recorded side by side, and one chosen with a reason.
 */
class Rfqs
{
    public const RELATIONS = [
        'lines.product:id,sku,name', 'suppliers:id,code,name', 'requisition:id,number,status',
        'quotations.supplier:id,code,name', 'quotations.lines', 'creator:id,name', 'awarder:id,name',
    ];

    public function __construct(
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function create(array $data, User $actor): PurchaseRfq
    {
        return DB::transaction(function () use ($data, $actor) {
            $requisition = null;

            if (! empty($data['purchase_requisition_id'])) {
                $requisition = PurchaseRequisition::query()->with('lines')->findOrFail($data['purchase_requisition_id']);

                if ($requisition->status !== PurchaseRequisition::STATUS_APPROVED) {
                    throw new RuntimeException("Requisition {$requisition->number} is {$requisition->status}; quotations are requested for approved requisitions only.");
                }
            }

            $rfq = PurchaseRfq::create([
                'number' => $this->numbers->next('RFQ'),
                'purchase_requisition_id' => $requisition?->id,
                'title' => $data['title'],
                'issue_date' => $data['issue_date'] ?? now()->toDateString(),
                'closing_date' => $data['closing_date'] ?? null,
                'notes' => $data['notes'] ?? null,
                'status' => PurchaseRfq::STATUS_DRAFT,
                'created_by' => $actor->id,
            ]);

            $lines = $data['lines'] ?? [];

            if (! $lines && $requisition) {
                $lines = $requisition->lines->map(fn ($l) => [
                    'purchase_requisition_line_id' => $l->id, 'line_type' => $l->line_type, 'product_id' => $l->product_id,
                    'description' => $l->description, 'quantity' => (float) $l->quantity, 'expense_account_id' => $l->expense_account_id,
                ])->all();
            }

            if (! $lines) {
                throw new RuntimeException('Add at least one line.');
            }

            foreach (array_values($lines) as $i => $line) {
                if ((float) ($line['quantity'] ?? 0) <= 0) {
                    throw new RuntimeException('Line '.($i + 1).': the quantity must be greater than zero.');
                }

                $rfq->lines()->create([
                    ...Lines::normalise($line, $i),
                    'purchase_requisition_line_id' => Lines::requisitionLine($requisition?->id, $line['purchase_requisition_line_id'] ?? null),
                    'quantity' => (float) $line['quantity'],
                ]);
            }

            $suppliers = Supplier::query()->whereIn('id', $data['supplier_ids'] ?? [])->where('is_active', true)->pluck('id');

            if ($suppliers->count() !== count(array_unique($data['supplier_ids'] ?? [])) || $suppliers->isEmpty()) {
                throw new RuntimeException('Invite at least one active supplier from this company\'s list.');
            }

            $rfq->suppliers()->sync($suppliers->all());
            $this->audit->log('procurement.rfq.created', "Prepared request for quotation {$rfq->number}", $rfq, actor: $actor);

            return $rfq->fresh(self::RELATIONS);
        });
    }

    public function send(PurchaseRfq $rfq, User $actor): PurchaseRfq
    {
        return DB::transaction(function () use ($rfq, $actor) {
            $locked = $this->lock($rfq);
            $this->assertStatus($locked, [PurchaseRfq::STATUS_DRAFT], 'sent');

            $locked->update(['status' => PurchaseRfq::STATUS_SENT]);
            $this->audit->log('procurement.rfq.sent', "Sent {$locked->number} to {$locked->suppliers()->count()} suppliers", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    /**
     * Records (or corrects, before the award) one supplier's quotation.
     *
     * @param  array<string, mixed>  $data
     */
    public function quote(PurchaseRfq $rfq, array $data, User $actor): SupplierQuotation
    {
        return DB::transaction(function () use ($rfq, $data, $actor) {
            $locked = $this->lock($rfq);
            $this->assertStatus($locked, [PurchaseRfq::STATUS_SENT], 'quoted against');

            $supplierId = (int) $data['supplier_id'];

            if (! $locked->suppliers()->whereKey($supplierId)->exists()) {
                throw new RuntimeException("That supplier was not invited to quote on {$locked->number}.");
            }

            $rfqLines = $locked->lines()->get()->keyBy('id');
            $prices = collect($data['lines'] ?? [])->keyBy('purchase_rfq_line_id');

            if ($rfqLines->keys()->diff($prices->keys())->isNotEmpty() || $prices->keys()->diff($rfqLines->keys())->isNotEmpty()) {
                throw new RuntimeException('Enter a price for every line of the request, and only for those lines.');
            }

            $quotation = SupplierQuotation::query()->firstOrNew(['purchase_rfq_id' => $locked->id, 'supplier_id' => $supplierId]);
            $quotation->fill([
                'reference' => $data['reference'] ?? null,
                'quotation_date' => $data['quotation_date'] ?? now()->toDateString(),
                'valid_until' => $data['valid_until'] ?? null,
                'lead_time_days' => $data['lead_time_days'] ?? null,
                'payment_terms' => $data['payment_terms'] ?? null,
                'delivery_terms' => $data['delivery_terms'] ?? null,
                'notes' => $data['notes'] ?? null,
                'status' => SupplierQuotation::STATUS_RECEIVED,
            ]);
            $quotation->created_by ??= $actor->id;
            $quotation->save();
            $quotation->lines()->delete();

            $subtotal = 0.0;
            $vat = 0.0;

            foreach ($rfqLines as $id => $line) {
                $price = (float) $prices[$id]['unit_price'];
                $rate = (float) ($prices[$id]['vat_rate'] ?? 0);
                $amount = Lines::money($price * (float) $line->quantity);
                $subtotal += $amount;
                $vat += Lines::money($amount * $rate / 100);

                $quotation->lines()->create(['purchase_rfq_line_id' => $id, 'unit_price' => $price, 'vat_rate' => $rate, 'amount' => $amount]);
            }

            $quotation->update(['subtotal' => Lines::money($subtotal), 'vat_amount' => Lines::money($vat), 'total' => Lines::money($subtotal + $vat)]);
            $this->audit->log('procurement.quotation.recorded', "Recorded quotation from supplier #{$supplierId} on {$locked->number}", $quotation, actor: $actor);

            return $quotation->fresh(['lines', 'supplier:id,code,name']);
        });
    }

    /**
     * Lines down, suppliers across: each supplier's unit price per line, the
     * lowest marked, and each supplier's total.
     *
     * @return array<string, mixed>
     */
    public function comparison(PurchaseRfq $rfq): array
    {
        $rfq->loadMissing(self::RELATIONS);
        $quotations = $rfq->quotations->sortBy('total')->values();

        $lines = $rfq->lines->map(function ($line) use ($quotations) {
            $prices = $quotations->mapWithKeys(fn ($q) => [$q->id => $q->lines->firstWhere('purchase_rfq_line_id', $line->id)]);
            $lowest = $prices->filter()->min(fn ($l) => (float) $l->unit_price);

            return [
                'id' => $line->id,
                'description' => $line->description,
                'line_type' => $line->line_type,
                'quantity' => (float) $line->quantity,
                'prices' => $quotations->map(fn ($q) => [
                    'quotation_id' => $q->id,
                    'unit_price' => $prices[$q->id] ? (float) $prices[$q->id]->unit_price : null,
                    'amount' => $prices[$q->id] ? (float) $prices[$q->id]->amount : null,
                    'lowest' => $prices[$q->id] && (float) $prices[$q->id]->unit_price === (float) $lowest,
                ])->values(),
            ];
        })->values();

        $lowestTotal = $quotations->min(fn ($q) => (float) $q->total);

        return [
            'quotations' => $quotations->map(fn ($q) => [
                'id' => $q->id,
                'supplier' => $q->supplier?->only(['id', 'code', 'name']),
                'reference' => $q->reference,
                'lead_time_days' => $q->lead_time_days,
                'payment_terms' => $q->payment_terms,
                'delivery_terms' => $q->delivery_terms,
                'valid_until' => $q->valid_until?->toDateString(),
                'subtotal' => (float) $q->subtotal,
                'vat_amount' => (float) $q->vat_amount,
                'total' => (float) $q->total,
                'status' => $q->status,
                'lowest' => (float) $q->total === (float) $lowestTotal,
            ])->values(),
            'lines' => $lines,
            'invited' => $rfq->suppliers->map->only(['id', 'code', 'name'])->values(),
        ];
    }

    public function award(PurchaseRfq $rfq, int $quotationId, string $reason, User $actor): PurchaseRfq
    {
        return DB::transaction(function () use ($rfq, $quotationId, $reason, $actor) {
            $locked = $this->lock($rfq);
            $this->assertStatus($locked, [PurchaseRfq::STATUS_SENT], 'awarded');

            $winner = $locked->quotations()->whereKey($quotationId)->first()
                ?? throw new RuntimeException("That quotation does not belong to {$locked->number}.");

            $locked->quotations()->whereKeyNot($winner->id)->update(['status' => SupplierQuotation::STATUS_NOT_SELECTED]);
            $winner->update(['status' => SupplierQuotation::STATUS_SELECTED]);

            $locked->update([
                'status' => PurchaseRfq::STATUS_AWARDED,
                'selected_quotation_id' => $winner->id,
                'selection_reason' => mb_substr($reason, 0, 500),
                'awarded_by' => $actor->id,
                'awarded_at' => now(),
            ]);

            $this->audit->log('procurement.rfq.awarded', "Awarded {$locked->number} to supplier #{$winner->supplier_id} · {$reason}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function cancel(PurchaseRfq $rfq, User $actor): PurchaseRfq
    {
        return DB::transaction(function () use ($rfq, $actor) {
            $locked = $this->lock($rfq);
            $this->assertStatus($locked, [PurchaseRfq::STATUS_DRAFT, PurchaseRfq::STATUS_SENT], 'cancelled');

            $locked->update(['status' => PurchaseRfq::STATUS_CANCELLED]);
            $this->audit->log('procurement.rfq.cancelled', "Cancelled {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    private function lock(PurchaseRfq $rfq): PurchaseRfq
    {
        return PurchaseRfq::query()->whereKey($rfq->id)->lockForUpdate()->firstOrFail();
    }

    /** @param  list<string>  $allowed */
    private function assertStatus(PurchaseRfq $rfq, array $allowed, string $verb): void
    {
        if (! in_array($rfq->status, $allowed, true)) {
            throw new RuntimeException("{$rfq->number} is {$rfq->status} and cannot be {$verb}.");
        }
    }
}
