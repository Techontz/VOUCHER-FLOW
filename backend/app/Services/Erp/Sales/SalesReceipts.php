<?php

namespace App\Services\Erp\Sales;

use App\Models\Erp\Account;
use App\Models\Erp\Sales\SalesInvoice;
use App\Models\Erp\Sales\SalesOrder;
use App\Models\Erp\Sales\SalesReceipt;
use App\Models\Erp\Sales\SalesReceiptAllocation;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Customer receipts. Recording one changes nothing on the books; finance
 * verification, by a different person from the one who recorded it, posts
 * it (Dr cash or bank, Cr receivable), applies it to its invoices and may
 * release prepayment orders for loading.
 */
class SalesReceipts
{
    public function __construct(
        private readonly SalesOrders $orders,
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    /** A cash or bank account: an active asset account coded 1100 to 1299. */
    public static function isCashAccount(?Account $account): bool
    {
        return $account && $account->type === 'asset' && $account->is_active
            && (int) $account->code >= 1100 && (int) $account->code <= 1299;
    }

    /**
     * @param  array<string, mixed>  $data
     * @param  list<array{sales_invoice_id: int, amount: float|string}>  $allocations
     */
    public function record(array $data, array $allocations, User $actor): SalesReceipt
    {
        return DB::transaction(function () use ($data, $allocations, $actor) {
            $customer = $this->orders->activeCustomer((int) $data['customer_id']);
            $account = Account::query()->find($data['account_id'] ?? 0);

            if (! self::isCashAccount($account)) {
                throw new RuntimeException('Receive money into a cash or bank account (an asset account coded 1100 to 1299).');
            }

            if (! $allocations) {
                throw new RuntimeException('Apply the receipt to at least one invoice.');
            }

            $total = 0;
            $rows = [];
            foreach ($allocations as $a) {
                $amount = round((float) $a['amount'], 2);
                if ($amount <= 0) {
                    continue;
                }

                $invoice = SalesInvoice::query()->whereKey($a['sales_invoice_id'])->lockForUpdate()->first();

                if (! $invoice || $invoice->customer_id !== $customer->id || $invoice->status !== SalesInvoice::STATUS_POSTED) {
                    throw new RuntimeException('A receipt can only be applied to posted invoices of the same customer.');
                }

                $pending = (float) SalesReceiptAllocation::query()->where('sales_invoice_id', $invoice->id)
                    ->whereHas('receipt', fn ($q) => $q->where('status', SalesReceipt::STATUS_RECORDED))->sum('amount');
                $open = round($invoice->balance - $pending, 2);

                if ($amount > $open + 0.004) {
                    throw new RuntimeException(sprintf('%s has TZS %s left to pay (after receipts awaiting verification); TZS %s is too much.', $invoice->number, number_format(max(0, $open), 2), number_format($amount, 2)));
                }

                $rows[] = ['sales_invoice_id' => $invoice->id, 'amount' => $amount];
                $total += (int) round($amount * 100);
            }

            if (! $rows) {
                throw new RuntimeException('Apply the receipt to at least one invoice.');
            }

            $receipt = SalesReceipt::create([
                'number' => $this->numbers->next('RCT'),
                'customer_id' => $customer->id,
                'account_id' => $account->id,
                'receipt_date' => $data['receipt_date'] ?? now()->toDateString(),
                'amount' => $total / 100,
                'method' => $data['method'] ?? 'bank_transfer',
                'reference' => $data['reference'] ?? null,
                'notes' => $data['notes'] ?? null,
                'status' => SalesReceipt::STATUS_RECORDED,
                'created_by' => $actor->id,
            ]);

            foreach ($rows as $row) {
                $receipt->allocations()->create($row);
            }

            $this->audit->log('sales.receipt.recorded', sprintf('Recorded receipt %s of TZS %s from %s', $receipt->number, number_format($total / 100, 2), $customer->name), $receipt, actor: $actor);

            return $receipt->load('allocations.invoice:id,number', 'customer', 'account:id,code,name');
        });
    }

    public function verify(SalesReceipt $receipt, User $actor): SalesReceipt
    {
        return DB::transaction(function () use ($receipt, $actor) {
            $locked = SalesReceipt::query()->whereKey($receipt->id)->lockForUpdate()->firstOrFail();
            SalesOrders::expect($locked->status, [SalesReceipt::STATUS_RECORDED], $locked->number, 'verified');

            if ($locked->created_by === $actor->id) {
                throw new RuntimeException('You recorded this payment, so someone else in finance must verify it.');
            }

            $orders = [];
            foreach ($locked->allocations as $allocation) {
                $invoice = SalesInvoice::query()->whereKey($allocation->sales_invoice_id)->lockForUpdate()->firstOrFail();

                if ((float) $allocation->amount > $invoice->balance + 0.004) {
                    throw new RuntimeException("{$invoice->number} no longer has TZS ".number_format((float) $allocation->amount, 2).' to pay. Reject this receipt and record it again.');
                }

                $invoice->update(['amount_paid' => round((float) $invoice->amount_paid + (float) $allocation->amount, 2)]);
                if ($invoice->sales_order_id) {
                    $orders[$invoice->sales_order_id] = true;
                }
            }

            $locked->update(['status' => SalesReceipt::STATUS_VERIFIED, 'verified_by' => $actor->id, 'verified_at' => now()]);

            if (BusinessConfig::of($this->tenant->company())->postsToLedger()) {
                $this->journal->post([
                    ['account_id' => $locked->account_id, 'debit' => (float) $locked->amount, 'description' => $locked->number],
                    ['account' => 'receivable', 'credit' => (float) $locked->amount, 'description' => $locked->number],
                ], "Customer receipt {$locked->number}", $locked->receipt_date->toDateString(), $locked, 'post', $actor);
            }

            $this->audit->log('sales.receipt.verified', "Verified receipt {$locked->number}", $locked, actor: $actor);

            foreach (array_keys($orders) as $orderId) {
                $order = SalesOrder::query()->whereKey($orderId)->lockForUpdate()->first();
                if ($order) {
                    $this->orders->refreshPayment($order, $actor);
                }
            }

            return $locked->fresh(['allocations.invoice:id,number,sales_order_id', 'customer', 'account:id,code,name', 'creator:id,name', 'verifier:id,name']);
        });
    }

    public function reject(SalesReceipt $receipt, string $reason, User $actor): SalesReceipt
    {
        return DB::transaction(function () use ($receipt, $reason, $actor) {
            $locked = SalesReceipt::query()->whereKey($receipt->id)->lockForUpdate()->firstOrFail();
            SalesOrders::expect($locked->status, [SalesReceipt::STATUS_RECORDED], $locked->number, 'rejected');
            $locked->update(['status' => SalesReceipt::STATUS_REJECTED, 'rejection_reason' => mb_substr($reason, 0, 500), 'verified_by' => $actor->id, 'verified_at' => now()]);
            $this->audit->log('sales.receipt.rejected', "Rejected receipt {$locked->number}: {$reason}", $locked, actor: $actor);

            return $locked;
        });
    }
}
