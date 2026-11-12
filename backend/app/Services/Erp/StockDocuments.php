<?php

namespace App\Services\Erp;

use App\Models\Erp\JournalEntry;
use App\Models\Erp\Product;
use App\Models\Erp\StockDocument;
use App\Models\Erp\StockDocumentLine;
use App\Models\Erp\StockMovement;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Services\AuditLogger;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Stock documents from draft to ledger.
 *
 * A draft can be edited freely and changes nothing. Posting is the single
 * moment stock moves: the document row is locked, its status re-checked, every
 * line written to the ledger and the value posted to the general ledger, all
 * in one transaction, so a document is posted completely or not at all, and
 * never twice. A posted document is corrected by reversing it, never by
 * editing it.
 *
 * Posting rules (when the accounting module is on):
 *   opening      Dr Inventory          Cr Opening balance equity
 *   grn          Dr Inventory          Cr Goods received not invoiced
 *   issue        Dr Stock issued       Cr Inventory
 *   adjustment   Dr/Cr Inventory       against Inventory adjustments
 *   count        as adjustment, for the variance only
 *   transfer     no entry, the value stays on the same Inventory account
 */
class StockDocuments
{
    public function __construct(
        private readonly StockLedger $ledger,
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    /**
     * @param  array<string, mixed>  $header
     * @param  list<array<string, mixed>>  $lines
     */
    public function create(string $type, array $header, array $lines, User $actor): StockDocument
    {
        return DB::transaction(function () use ($type, $header, $lines, $actor) {
            $document = StockDocument::create([
                ...$this->header($type, $header),
                'type' => $type,
                'number' => $this->numbers->next(StockDocument::PREFIXES[$type]),
                'status' => StockDocument::STATUS_DRAFT,
                'created_by' => $actor->id,
            ]);

            $this->writeLines($document, $lines);
            $this->audit->log("stock.{$type}.created", "Prepared {$document->number}", $document, actor: $actor);

            return $document->load('lines.product.unit', 'warehouse', 'toWarehouse', 'supplier');
        });
    }

    /**
     * @param  array<string, mixed>  $header
     * @param  list<array<string, mixed>>  $lines
     */
    public function update(StockDocument $document, array $header, array $lines, User $actor): StockDocument
    {
        return DB::transaction(function () use ($document, $header, $lines, $actor) {
            $locked = $this->lock($document);
            $this->assertDraft($locked, 'edited');

            $locked->update($this->header($locked->type, $header));
            $locked->lines()->delete();
            $this->writeLines($locked, $lines);

            $this->audit->log("stock.{$locked->type}.updated", "Edited draft {$locked->number}", $locked, actor: $actor);

            return $locked->load('lines.product.unit', 'warehouse', 'toWarehouse', 'supplier');
        });
    }

    public function post(StockDocument $document, User $actor): StockDocument
    {
        return DB::transaction(function () use ($document, $actor) {
            $locked = $this->lock($document);
            $this->assertDraft($locked, 'posted');

            $lines = $locked->lines()->with('product.unit')->get();

            if ($lines->isEmpty()) {
                throw new RuntimeException("{$locked->number} has no lines to post.");
            }

            $from = $locked->warehouse;
            $to = $locked->toWarehouse;
            $date = $locked->document_date->toDateString();
            $movements = collect();

            foreach ($lines as $line) {
                $this->assertLine($locked, $line->product, $line->toArray());
                $movements->push(...$this->moveLine($locked, $line, $from, $to, $date, $actor));
            }

            $locked->update([
                'status' => StockDocument::STATUS_POSTED,
                'posted_by' => $actor->id,
                'posted_at' => now(),
            ]);

            $this->postToLedger($locked, $movements, $actor);
            $this->audit->log("stock.{$locked->type}.posted", "Posted {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(['lines.product.unit', 'warehouse', 'toWarehouse', 'supplier', 'movements']);
        });
    }

    /**
     * Undoes a posted document with a second, posted document that moves every
     * quantity back at the cost it moved at. Both stay on the record.
     */
    public function reverse(StockDocument $document, string $reason, User $actor): StockDocument
    {
        return DB::transaction(function () use ($document, $reason, $actor) {
            $locked = $this->lock($document);

            if ($locked->status !== StockDocument::STATUS_POSTED) {
                throw new RuntimeException("Only a posted document can be reversed; {$locked->number} is {$locked->status}.");
            }

            if ($locked->reversal_of_id) {
                throw new RuntimeException("{$locked->number} is itself a reversal.");
            }

            $reversal = StockDocument::create([
                'type' => $locked->type,
                'number' => $this->numbers->next('REV'),
                'document_date' => now()->toDateString(),
                'status' => StockDocument::STATUS_POSTED,
                'warehouse_id' => $locked->warehouse_id,
                'to_warehouse_id' => $locked->to_warehouse_id,
                'supplier_id' => $locked->supplier_id,
                'reference' => $locked->number,
                'reason' => mb_substr($reason, 0, 255),
                'reversal_of_id' => $locked->id,
                'created_by' => $actor->id,
                'posted_by' => $actor->id,
                'posted_at' => now(),
            ]);

            $original = $locked->movements()->with('product', 'warehouse')->get();
            $lineMap = [];

            // Undo outbound legs first, so a transfer's destination gives the
            // stock back before its source takes it.
            foreach ($original->sortByDesc(fn ($m) => (float) $m->quantity) as $movement) {
                $lineMap[$movement->stock_document_line_id] ??= $reversal->lines()->create(
                    StockDocumentLine::query()->findOrFail($movement->stock_document_line_id)
                        ->only(['product_id', 'quantity', 'unit_cost', 'batch_number', 'expiry_date', 'serial_number'])
                )->id;

                $this->ledger->move($movement->product, $movement->warehouse, -1 * (float) $movement->quantity, [
                    'type' => 'reversal',
                    'reference' => $reversal->number,
                    'reason' => "Reversal of {$locked->number}",
                    'batch_number' => $movement->batch_number,
                    'expiry_date' => $movement->expiry_date?->toDateString(),
                    'unit_cost' => $movement->unit_cost,
                    'document_id' => $reversal->id,
                    'line_id' => $lineMap[$movement->stock_document_line_id],
                    'actor' => $actor,
                ]);
            }

            $locked->update(['status' => StockDocument::STATUS_REVERSED]);

            if ($entry = $this->journal->existing($locked)) {
                if ($entry->status === JournalEntry::STATUS_POSTED) {
                    $this->journal->reverse($entry, "Stock document {$locked->number} reversed", $actor);
                }
            }

            $this->audit->log("stock.{$locked->type}.reversed", "Reversed {$locked->number} with {$reversal->number} · {$reason}", $locked, actor: $actor);

            return $reversal->load('lines.product.unit', 'warehouse', 'toWarehouse', 'movements');
        });
    }

    public function cancel(StockDocument $document, User $actor): StockDocument
    {
        return DB::transaction(function () use ($document, $actor) {
            $locked = $this->lock($document);
            $this->assertDraft($locked, 'cancelled');

            $locked->update(['status' => StockDocument::STATUS_CANCELLED]);
            $this->audit->log("stock.{$locked->type}.cancelled", "Cancelled draft {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    /**
     * Refuses a line the ledger could not honestly record.
     *
     * @param  array<string, mixed>  $line
     */
    public function assertLine(StockDocument $document, Product $product, array $line): void
    {
        $type = $document->type;
        $quantity = (float) ($line['quantity'] ?? 0);
        $name = $product->name;

        if (! $product->isStocked()) {
            throw new RuntimeException("{$name} is a service and cannot be held in stock.");
        }

        if (! $product->is_active) {
            throw new RuntimeException("{$name} is inactive.");
        }

        if ($type === StockDocument::TYPE_COUNT ? $quantity < 0 : ($type === StockDocument::TYPE_ADJUSTMENT ? $quantity == 0 : $quantity <= 0)) {
            throw new RuntimeException(match ($type) {
                StockDocument::TYPE_COUNT => "{$name}: a counted quantity cannot be negative.",
                StockDocument::TYPE_ADJUSTMENT => "{$name}: an adjustment needs a quantity (positive found, negative lost).",
                default => "{$name}: the quantity must be greater than zero.",
            });
        }

        if (! $product->unit?->allows_decimals && floor(abs($quantity)) != abs($quantity)) {
            throw new RuntimeException("{$name} is counted in whole {$product->unit?->name}s.");
        }

        if (in_array($type, [StockDocument::TYPE_OPENING, StockDocument::TYPE_GRN], true)
            && (! isset($line['unit_cost']) || $line['unit_cost'] === '' || (float) $line['unit_cost'] < 0)) {
            throw new RuntimeException("{$name}: enter the unit cost received.");
        }

        if ($product->track_batches && blank($line['batch_number'] ?? null)) {
            throw new RuntimeException("{$name} is batch-tracked: enter the batch number.");
        }

        $inbound = in_array($type, [StockDocument::TYPE_OPENING, StockDocument::TYPE_GRN], true)
            || ($type === StockDocument::TYPE_ADJUSTMENT && $quantity > 0);

        if ($product->track_expiry && $inbound && blank($line['expiry_date'] ?? null)) {
            throw new RuntimeException("{$name} tracks expiry: enter the expiry date.");
        }

        if ($product->track_serials && $type !== StockDocument::TYPE_COUNT) {
            if (blank($line['serial_number'] ?? null) || abs($quantity) != 1) {
                throw new RuntimeException("{$name} is serial-tracked: one line per unit, each with its serial number.");
            }
        }
    }

    /** @return list<StockMovement> */
    private function moveLine(StockDocument $document, StockDocumentLine $line, Warehouse $from, ?Warehouse $to, string $date, User $actor): array
    {
        $base = [
            'reference' => $document->number,
            'reason' => $document->reason,
            'date' => $date,
            'batch_number' => $line->batch_number,
            'expiry_date' => $line->expiry_date?->toDateString(),
            'document_id' => $document->id,
            'line_id' => $line->id,
            'actor' => $actor,
        ];
        $quantity = (float) $line->quantity;
        $product = $line->product;

        return match ($document->type) {
            StockDocument::TYPE_OPENING, StockDocument::TYPE_GRN => [
                $this->ledger->move($product, $from, $quantity, [...$base, 'type' => $document->type, 'unit_cost' => $line->unit_cost]),
            ],
            StockDocument::TYPE_ISSUE => [
                $this->ledger->move($product, $from, -$quantity, [...$base, 'type' => 'issue']),
            ],
            StockDocument::TYPE_TRANSFER => $this->transfer($product, $from, $to, $quantity, $base),
            StockDocument::TYPE_ADJUSTMENT => [
                $this->ledger->move($product, $from, $quantity, [...$base, 'type' => 'adjustment', 'unit_cost' => $quantity > 0 ? $line->unit_cost : null]),
            ],
            StockDocument::TYPE_COUNT => $this->count($line, $from, $base),
        };
    }

    /** @return list<StockMovement> */
    private function transfer(Product $product, Warehouse $from, ?Warehouse $to, float $quantity, array $base): array
    {
        $out = $this->ledger->move($product, $from, -$quantity, [...$base, 'type' => 'transfer_out']);
        $in = $this->ledger->move($product, $to, $quantity, [...$base, 'type' => 'transfer_in', 'unit_cost' => $out->unit_cost]);

        return [$out, $in];
    }

    /** A count moves only the difference between what was counted and what the ledger held. */
    private function count(StockDocumentLine $line, Warehouse $warehouse, array $base): array
    {
        $system = $this->ledger->onHand($line->product, $warehouse, (string) ($line->batch_number ?? ''));
        $line->forceFill(['system_quantity' => $system])->save();

        $variance = round((float) $line->quantity - $system, 4);

        return abs($variance) < 0.00005 ? [] : [
            $this->ledger->move($line->product, $warehouse, $variance, [...$base, 'type' => 'count']),
        ];
    }

    /** @param  Collection<int, StockMovement>  $movements */
    private function postToLedger(StockDocument $document, Collection $movements, User $actor): void
    {
        if (! BusinessConfig::of($this->tenant->company())->postsToLedger() || $document->type === StockDocument::TYPE_TRANSFER) {
            return;
        }

        $value = round($movements->sum(fn ($m) => (float) $m->value), 2);

        if (abs($value) < 0.005) {
            return;
        }

        $amount = abs($value);
        [$debit, $credit] = match ($document->type) {
            StockDocument::TYPE_OPENING => ['inventory', 'opening_equity'],
            StockDocument::TYPE_GRN => ['inventory', $document->contra_account ?: 'grni'],
            StockDocument::TYPE_ISSUE => [$document->contra_account ?: 'stock_issues', 'inventory'],
            default => $value > 0 ? ['inventory', 'stock_adjustments'] : ['stock_adjustments', 'inventory'],
        };

        $this->journal->post([
            ['account' => $debit, 'debit' => $amount, 'description' => $document->number],
            ['account' => $credit, 'credit' => $amount, 'description' => $document->number],
        ], ucfirst($document->type)." {$document->number}", $document->document_date->toDateString(), $document, 'post', $actor);
    }

    /** @return array<string, mixed> */
    private function header(string $type, array $header): array
    {
        $warehouse = (int) ($header['warehouse_id'] ?? 0);
        $to = isset($header['to_warehouse_id']) ? (int) $header['to_warehouse_id'] : null;

        if ($type === StockDocument::TYPE_TRANSFER && (! $to || $to === $warehouse)) {
            throw new RuntimeException('A transfer needs a destination different from its source.');
        }

        return [
            'document_date' => $header['document_date'] ?? now()->toDateString(),
            'warehouse_id' => $warehouse,
            'to_warehouse_id' => $type === StockDocument::TYPE_TRANSFER ? $to : null,
            'supplier_id' => $type === StockDocument::TYPE_GRN ? ($header['supplier_id'] ?? null) : null,
            'reference' => $header['reference'] ?? null,
            'reason' => $header['reason'] ?? null,
            'notes' => $header['notes'] ?? null,
            // Set by the module that raised the document, never by a person.
            'source_type' => $header['source_type'] ?? null,
            'source_id' => $header['source_id'] ?? null,
            'contra_account' => $header['contra_account'] ?? null,
        ];
    }

    /** @param  list<array<string, mixed>>  $lines */
    private function writeLines(StockDocument $document, array $lines): void
    {
        if (! $lines) {
            throw new RuntimeException('Add at least one line.');
        }

        $products = Product::query()->with('unit')->whereIn('id', array_column($lines, 'product_id'))->get()->keyBy('id');

        foreach ($lines as $line) {
            $product = $products[$line['product_id']] ?? throw new RuntimeException('One of the products is not in this company\'s catalogue.');
            // Checked on the way in as well as at posting, so a draft that
            // can never post is caught while the person is still typing.
            $this->assertLine($document, $product, $line);

            $document->lines()->create([
                'product_id' => $product->id,
                'quantity' => $line['quantity'],
                'unit_cost' => $line['unit_cost'] ?? null,
                'batch_number' => $line['batch_number'] ?? null,
                'expiry_date' => $line['expiry_date'] ?? null,
                'serial_number' => $line['serial_number'] ?? null,
                'note' => $line['note'] ?? null,
            ]);
        }
    }

    private function lock(StockDocument $document): StockDocument
    {
        return StockDocument::query()->whereKey($document->id)->lockForUpdate()->firstOrFail();
    }

    private function assertDraft(StockDocument $document, string $verb): void
    {
        if (! $document->isDraft()) {
            throw new RuntimeException("{$document->number} is {$document->status} and cannot be {$verb}.");
        }
    }
}
