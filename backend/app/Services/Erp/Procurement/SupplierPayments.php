<?php

namespace App\Services\Erp\Procurement;

use App\Models\Erp\Account;
use App\Models\Erp\Procurement\SupplierInvoice;
use App\Models\Erp\Procurement\SupplierPayment;
use App\Models\Erp\Supplier;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Payments to suppliers. A payment is allocated in full to posted invoices of
 * the same supplier, never beyond what each still owes, and posts once:
 * Dr Accounts payable, Cr the cash or bank account it was paid from.
 */
class SupplierPayments
{
    public const RELATIONS = [
        'allocations.invoice:id,number,supplier_invoice_number,invoice_date,due_date,total,amount_paid,status',
        'supplier:id,code,name', 'account:id,code,name', 'journal:id,number,status', 'creator:id,name', 'poster:id,name',
    ];

    public function __construct(
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly JournalPoster $journal,
        private readonly TenantContext $tenant,
    ) {}

    /** Cash and bank: asset accounts coded 1100 to 1299. */
    public static function isCashOrBank(?Account $account): bool
    {
        return $account !== null && $account->type === 'asset' && $account->is_active
            && ctype_digit((string) $account->code) && (int) $account->code >= 1100 && (int) $account->code <= 1299;
    }

    /** @param  array<string, mixed>  $data */
    public function create(array $data, User $actor): SupplierPayment
    {
        return DB::transaction(function () use ($data, $actor) {
            $supplier = Supplier::query()->findOrFail($data['supplier_id']);
            $account = Account::query()->find($data['account_id']);

            if (! self::isCashOrBank($account)) {
                throw new RuntimeException('Pay from an active cash or bank account (asset accounts 1100 to 1299).');
            }

            $amount = Lines::money((float) $data['amount']);
            $allocations = $this->checkAllocations($supplier->id, $amount, $data['allocations'] ?? []);

            $payment = SupplierPayment::create([
                'number' => $this->numbers->next('SPAY'),
                'supplier_id' => $supplier->id,
                'account_id' => $account->id,
                'payment_date' => $data['payment_date'] ?? now()->toDateString(),
                'method' => $data['method'] ?? 'bank_transfer',
                'reference' => $data['reference'] ?? null,
                'amount' => $amount,
                'notes' => $data['notes'] ?? null,
                'status' => SupplierPayment::STATUS_DRAFT,
                'created_by' => $actor->id,
            ]);

            foreach ($allocations as $invoiceId => $value) {
                $payment->allocations()->create(['supplier_invoice_id' => $invoiceId, 'amount' => $value]);
            }

            $this->audit->log('procurement.payment.created', "Prepared payment {$payment->number} to {$supplier->name}", $payment, actor: $actor);

            return $payment->fresh(self::RELATIONS);
        });
    }

    public function post(SupplierPayment $payment, User $actor): SupplierPayment
    {
        return DB::transaction(function () use ($payment, $actor) {
            $locked = SupplierPayment::query()->whereKey($payment->id)->lockForUpdate()->firstOrFail();

            if ($locked->status !== SupplierPayment::STATUS_DRAFT) {
                throw new RuntimeException("{$locked->number} is {$locked->status} and cannot be posted.");
            }

            $allocations = $locked->allocations()->get();
            $invoices = SupplierInvoice::query()->whereIn('id', $allocations->pluck('supplier_invoice_id'))->lockForUpdate()->get()->keyBy('id');

            // Checked again under the lock: another payment may have settled an invoice since this one was prepared.
            foreach ($allocations as $allocation) {
                $invoice = $invoices[$allocation->supplier_invoice_id];

                if ((float) $allocation->amount > $invoice->outstanding + 0.004) {
                    throw new RuntimeException("{$invoice->number} now has only ".number_format($invoice->outstanding, 2)." outstanding; correct the allocation before posting {$locked->number}.");
                }
            }

            $entry = null;
            if (BusinessConfig::of($this->tenant->company())->postsToLedger()) {
                $entry = $this->journal->post([
                    ['account' => 'payable', 'debit' => (float) $locked->amount, 'description' => $locked->number],
                    ['account_id' => $locked->account_id, 'credit' => (float) $locked->amount, 'description' => $locked->reference ?: $locked->number],
                ], "Supplier payment {$locked->number}", $locked->payment_date->toDateString(), $locked, 'post', $actor);
            }

            foreach ($allocations as $allocation) {
                $invoices[$allocation->supplier_invoice_id]->increment('amount_paid', (float) $allocation->amount);
            }

            $locked->update(['status' => SupplierPayment::STATUS_POSTED, 'posted_by' => $actor->id, 'posted_at' => now(), 'journal_entry_id' => $entry?->id]);
            $this->audit->log('procurement.payment.posted', "Posted supplier payment {$locked->number}".($entry ? " as journal {$entry->number}" : ''), $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    public function cancel(SupplierPayment $payment, User $actor): SupplierPayment
    {
        return DB::transaction(function () use ($payment, $actor) {
            $locked = SupplierPayment::query()->whereKey($payment->id)->lockForUpdate()->firstOrFail();

            if ($locked->status !== SupplierPayment::STATUS_DRAFT) {
                throw new RuntimeException("{$locked->number} is {$locked->status} and cannot be cancelled.");
            }

            $locked->update(['status' => SupplierPayment::STATUS_CANCELLED]);
            $this->audit->log('procurement.payment.cancelled', "Cancelled supplier payment {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(self::RELATIONS);
        });
    }

    /**
     * @param  list<array{supplier_invoice_id: int, amount: float|string}>  $rows
     * @return array<int, float> invoice id => amount
     */
    private function checkAllocations(int $supplierId, float $amount, array $rows): array
    {
        if ($amount <= 0) {
            throw new RuntimeException('The payment amount must be greater than zero.');
        }

        $allocations = [];
        foreach ($rows as $row) {
            $value = Lines::money((float) ($row['amount'] ?? 0));
            if ($value > 0) {
                $allocations[(int) $row['supplier_invoice_id']] = ($allocations[(int) $row['supplier_invoice_id']] ?? 0) + $value;
            }
        }

        if (! $allocations) {
            throw new RuntimeException('Allocate the payment to at least one invoice.');
        }

        $invoices = SupplierInvoice::query()->whereIn('id', array_keys($allocations))->get()->keyBy('id');

        foreach ($allocations as $id => $value) {
            $invoice = $invoices[$id] ?? throw new RuntimeException('One of the invoices is not in this company\'s books.');

            if ($invoice->supplier_id !== $supplierId) {
                throw new RuntimeException("{$invoice->number} belongs to another supplier.");
            }

            if ($invoice->status !== SupplierInvoice::STATUS_POSTED) {
                throw new RuntimeException("{$invoice->number} is {$invoice->status}; only posted invoices can be paid.");
            }

            if ($value > $invoice->outstanding + 0.004) {
                throw new RuntimeException("{$invoice->number} has ".number_format($invoice->outstanding, 2).' outstanding; allocate no more than that.');
            }
        }

        if (abs(array_sum($allocations) - $amount) > 0.004) {
            throw new RuntimeException(sprintf('The allocations (%s) must add up to the payment amount (%s).', number_format(array_sum($allocations), 2), number_format($amount, 2)));
        }

        return $allocations;
    }
}
