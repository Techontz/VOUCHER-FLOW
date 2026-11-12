<?php

namespace App\Services\Erp\Sales;

use App\Models\Erp\Product;
use App\Models\Erp\Sales\SalesCreditNote;
use App\Models\Erp\Sales\SalesInvoice;
use App\Models\Erp\Sales\SalesInvoiceLine;
use App\Models\Erp\StockBalance;
use App\Models\Erp\StockDocument;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use App\Services\Erp\StockDocuments;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Credit notes and returns against a posted invoice, at the invoice's own
 * prices and VAT. Posting reverses the revenue and the VAT once:
 *
 *   Dr Sales returns (net)   Dr VAT payable (VAT)   Cr Accounts receivable (total)
 *
 * A return also brings the goods back through a posted GRN raised from the
 * credit note (Dr Inventory, Cr Cost of goods sold), at the warehouse's
 * average cost.
 */
class SalesCreditNotes
{
    public function __construct(
        private readonly StockDocuments $stock,
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    /**
     * @param  array<string, mixed>  $data  sales_invoice_id, reason, credit_date, return_to_stock, warehouse_id
     * @param  list<array{sales_invoice_line_id: int, quantity: float|string, batch_number?: ?string, expiry_date?: ?string}>  $lines
     */
    public function create(array $data, array $lines, User $actor): SalesCreditNote
    {
        return DB::transaction(function () use ($data, $lines, $actor) {
            $invoice = SalesInvoice::query()->whereKey($data['sales_invoice_id'])->lockForUpdate()->first()
                ?? throw new RuntimeException('That invoice is not in this company.');

            if ($invoice->status !== SalesInvoice::STATUS_POSTED) {
                throw new RuntimeException("Only a posted invoice can be credited; {$invoice->number} is {$invoice->status}.");
            }

            $return = (bool) ($data['return_to_stock'] ?? false);
            $warehouse = null;
            if ($return) {
                $warehouse = Warehouse::query()->where('is_active', true)->find($data['warehouse_id'] ?? 0)
                    ?? throw new RuntimeException('Choose the warehouse the returned goods go back to.');
            }

            $rows = [];
            foreach ($lines as $l) {
                $quantity = round((float) $l['quantity'], 3);
                if ($quantity <= 0) {
                    continue;
                }

                $line = SalesInvoiceLine::query()->where('sales_invoice_id', $invoice->id)->whereKey($l['sales_invoice_line_id'])->lockForUpdate()->first()
                    ?? throw new RuntimeException("A line does not belong to {$invoice->number}.");
                $open = round((float) $line->quantity - (float) $line->quantity_credited, 3);

                if ($quantity > $open + 0.0005) {
                    throw new RuntimeException(sprintf('%s: only %s left to credit on %s.', $line->product?->name, rtrim(rtrim(number_format($open, 3, '.', ''), '0'), '.'), $invoice->number));
                }

                $line->update(['quantity_credited' => (float) $line->quantity_credited + $quantity]);
                $rows[] = [
                    'sales_invoice_line_id' => $line->id,
                    'product_id' => $line->product_id,
                    'quantity' => $quantity,
                    'batch_number' => $l['batch_number'] ?? null,
                    'expiry_date' => $l['expiry_date'] ?? null,
                    ...SalesPricing::amounts($quantity, (float) $line->unit_price, (float) $line->discount_percent, (float) $line->tax_rate),
                ];
            }

            if (! $rows) {
                throw new RuntimeException('Credit at least one line.');
            }

            $note = SalesCreditNote::create([
                'number' => $this->numbers->next('CN'),
                'customer_id' => $invoice->customer_id,
                'sales_invoice_id' => $invoice->id,
                'credit_date' => $data['credit_date'] ?? now()->toDateString(),
                'reason' => mb_substr((string) $data['reason'], 0, 255),
                'status' => SalesCreditNote::STATUS_DRAFT,
                'return_to_stock' => $return,
                'warehouse_id' => $warehouse?->id,
                ...SalesPricing::totals($rows),
                'created_by' => $actor->id,
            ]);

            foreach ($rows as $row) {
                $note->lines()->create($row);
            }

            $this->audit->log('sales.credit_note.created', "Prepared credit note {$note->number} against {$invoice->number}", $note, actor: $actor);

            return $note->load('lines.product.unit', 'invoice:id,number', 'customer');
        });
    }

    public function post(SalesCreditNote $note, User $actor): SalesCreditNote
    {
        return DB::transaction(function () use ($note, $actor) {
            $locked = SalesCreditNote::query()->whereKey($note->id)->lockForUpdate()->firstOrFail();
            SalesOrders::expect($locked->status, [SalesCreditNote::STATUS_DRAFT], $locked->number, 'posted');
            $invoice = SalesInvoice::query()->whereKey($locked->sales_invoice_id)->lockForUpdate()->firstOrFail();

            $document = null;
            if ($locked->return_to_stock) {
                $document = $this->returnGoods($locked, $actor);
            }

            $locked->update([
                'status' => SalesCreditNote::STATUS_POSTED, 'posted_by' => $actor->id, 'posted_at' => now(),
                'stock_document_id' => $document?->id,
            ]);
            $invoice->update(['amount_credited' => round((float) $invoice->amount_credited + (float) $locked->total, 2)]);

            if (BusinessConfig::of($this->tenant->company())->postsToLedger()) {
                $lines = [
                    ['account' => 'sales_returns', 'debit' => round((float) $locked->subtotal - (float) $locked->discount_total, 2), 'description' => $locked->number],
                    ['account' => 'receivable', 'credit' => (float) $locked->total, 'description' => $locked->number],
                ];
                if ((float) $locked->tax_total > 0) {
                    $lines[] = ['account' => 'vat_output', 'debit' => (float) $locked->tax_total, 'description' => "VAT {$locked->number}"];
                }
                $this->journal->post($lines, "Credit note {$locked->number} against {$invoice->number}", $locked->credit_date->toDateString(), $locked, 'post', $actor);
            }

            $this->audit->log('sales.credit_note.posted', "Posted credit note {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(['lines.product.unit', 'invoice:id,number', 'customer', 'stockDocument:id,number']);
        });
    }

    public function cancel(SalesCreditNote $note, User $actor): SalesCreditNote
    {
        return DB::transaction(function () use ($note, $actor) {
            $locked = SalesCreditNote::query()->whereKey($note->id)->lockForUpdate()->firstOrFail();
            SalesOrders::expect($locked->status, [SalesCreditNote::STATUS_DRAFT], $locked->number, 'cancelled');

            foreach ($locked->lines as $line) {
                SalesInvoiceLine::query()->whereKey($line->sales_invoice_line_id)->lockForUpdate()->first()
                    ?->decrement('quantity_credited', (float) $line->quantity);
            }

            $locked->update(['status' => SalesCreditNote::STATUS_CANCELLED]);
            $this->audit->log('sales.credit_note.cancelled', "Cancelled draft credit note {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    private function returnGoods(SalesCreditNote $note, User $actor): StockDocument
    {
        $lines = [];
        foreach ($note->lines()->with('product')->get() as $line) {
            /** @var Product $product */
            $product = $line->product;
            if (! $product->isStocked()) {
                continue;
            }

            $cost = StockBalance::query()->where('product_id', $product->id)->where('warehouse_id', $note->warehouse_id)
                ->where('batch_number', (string) $line->batch_number)->value('average_cost')
                ?? StockBalance::query()->where('product_id', $product->id)->where('quantity', '>', 0)->avg('average_cost')
                ?? $product->cost_price;

            $lines[] = [
                'product_id' => $product->id,
                'quantity' => (float) $line->quantity,
                'unit_cost' => round((float) $cost, 2),
                'batch_number' => $line->batch_number,
                'expiry_date' => $line->expiry_date?->toDateString(),
                'note' => "Returned on {$note->number}",
            ];
        }

        if (! $lines) {
            throw new RuntimeException("{$note->number} has no stocked goods to return; post it as a credit only.");
        }

        $document = $this->stock->create(StockDocument::TYPE_GRN, [
            'warehouse_id' => $note->warehouse_id,
            'document_date' => $note->credit_date->toDateString(),
            'reference' => $note->number,
            'reason' => "Customer return: {$note->reason}",
            'source_type' => 'credit_note',
            'source_id' => $note->id,
            'contra_account' => 'cogs',
        ], $lines, $actor);

        return $this->stock->post($document, $actor);
    }
}
