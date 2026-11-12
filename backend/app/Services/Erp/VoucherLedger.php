<?php

namespace App\Services\Erp;

use App\Models\Department;
use App\Models\Erp\Account;
use App\Models\Erp\Procurement\SupplierInvoice;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherPayment;
use App\Models\VoucherType;
use App\Services\AmountFormatter;
use App\Services\AuditLogger;
use App\Services\Erp\Procurement\SupplierPayments;
use App\Services\VoucherNumberGenerator;
use App\Services\WorkflowEngine;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Where VouchFlow meets the books.
 *
 * A supplier invoice can raise a payment voucher, which then travels the
 * company's own route (HOD signature, CEO approval) exactly like any other.
 * When the cashier releases money on it, that release is posted for real:
 * a supplier payment allocated to the invoice (Dr payable, Cr bank or cash),
 * so the invoice, the supplier's statement and the ledger all move together.
 *
 * A voucher not raised from an invoice may name the account it charges; its
 * payments then post Dr that account, Cr bank or cash. Either way each
 * release posts once, inside the same transaction as the payment itself, so
 * a payment the books refuse is not recorded as paid either.
 */
class VoucherLedger
{
    public const SOURCE_SUPPLIER_INVOICE = 'supplier_invoice';

    public function __construct(
        private readonly SupplierPayments $supplierPayments,
        private readonly JournalPoster $journal,
        private readonly WorkflowEngine $engine,
        private readonly VoucherNumberGenerator $numbers,
        private readonly AmountFormatter $money,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    /** A draft payment voucher for what is still owed on a posted supplier invoice. */
    public function raiseFromSupplierInvoice(SupplierInvoice $invoice, User $actor): Voucher
    {
        return DB::transaction(function () use ($invoice, $actor) {
            $invoice = SupplierInvoice::query()->with('supplier')->lockForUpdate()->findOrFail($invoice->id);
            $outstanding = $invoice->outstanding;

            if ($invoice->status !== SupplierInvoice::STATUS_POSTED) {
                throw new RuntimeException('Only a posted supplier invoice can raise a payment voucher.');
            }
            if ($outstanding <= 0.004) {
                throw new RuntimeException("{$invoice->number} is already paid in full.");
            }
            if ($open = $this->openVoucherFor(self::SOURCE_SUPPLIER_INVOICE, $invoice->id)) {
                throw new RuntimeException("{$invoice->number} already has payment voucher {$open->number} on its way.");
            }

            $type = VoucherType::query()->where('code', 'payment')->where('is_active', true)->first()
                ?? VoucherType::query()->where('is_active', true)->firstOrFail();
            $company = $this->tenant->company();
            $supplier = $invoice->supplier;
            $currency = $company?->currency ?? 'TZS';

            $voucher = Voucher::create([
                'company_id' => $company?->id,
                'number' => $this->numbers->next($type),
                'voucher_type_id' => $type->id,
                'workflow_id' => $this->engine->resolveWorkflow($type)?->id,
                // The raiser's own department routes the signature; failing
                // that, finance, whose payable this is.
                'department_id' => $actor->department_id
                    ?? Department::query()->where('name', 'like', '%finance%')->value('id'),
                'requester_id' => $actor->id,
                'payee' => $supplier->name,
                'purpose' => "Payment of {$supplier->name} invoice {$invoice->supplier_invoice_number}",
                'description' => "Supplier invoice {$invoice->number} ({$invoice->supplier_invoice_number}), due {$invoice->due_date?->toDateString()}.",
                'amount' => $outstanding,
                'currency' => $currency,
                'amount_in_words' => $this->money->inWords($outstanding, $currency),
                'payment_method' => 'Bank Transfer',
                'kind' => Voucher::KIND_BANK,
                'payee_bank' => $supplier->bank_name,
                'payee_account_name' => $supplier->bank_account_name,
                'payee_account_number' => $supplier->bank_account_number,
                'voucher_date' => now()->toDateString(),
                'status' => Voucher::STATUS_DRAFT,
                'verification_code' => $this->numbers->verificationCode(),
                'source_type' => self::SOURCE_SUPPLIER_INVOICE,
                'source_id' => $invoice->id,
                'source_label' => "{$invoice->number} · {$supplier->name}",
                'created_by' => $actor->id,
                'updated_by' => $actor->id,
            ]);

            $this->engine->record($voucher, $actor, 'created');
            $this->audit->log('voucher.raised_from_invoice', "Raised voucher {$voucher->number} from supplier invoice {$invoice->number}", $voucher, actor: $actor);

            return $voucher;
        });
    }

    /**
     * Posts one release of money on a voucher. Called by the workflow engine
     * inside the payment's transaction; does nothing for a voucher that is
     * neither linked to an invoice nor coded to an account, or when the
     * company does not keep its books here.
     */
    public function recordPayment(Voucher $voucher, VoucherPayment $payment, User $actor): void
    {
        $company = $this->tenant->company();
        if (! $company || ! BusinessConfig::of($company)->postsToLedger()) {
            return;
        }

        $isLinked = $voucher->source_type === self::SOURCE_SUPPLIER_INVOICE && $voucher->source_id;
        if (! $isLinked && ! $voucher->ledger_account_id) {
            return;
        }

        $from = $this->payingAccount($voucher, $payment);
        $amount = round((float) $payment->amount, 2);
        $reference = $payment->payment_reference ?: "{$voucher->number}/{$payment->sequence}";

        if ($isLinked) {
            $invoice = SupplierInvoice::query()->find($voucher->source_id)
                ?? throw new RuntimeException('The supplier invoice this voucher pays no longer exists.');

            if ($amount > $invoice->outstanding + 0.004) {
                throw new RuntimeException("Only {$voucher->currency} ".number_format($invoice->outstanding, 2)." is still owed on {$invoice->number}.");
            }

            $supplierPayment = $this->supplierPayments->create([
                'supplier_id' => $invoice->supplier_id,
                'account_id' => $from->id,
                'amount' => $amount,
                'payment_date' => $payment->payment_date?->toDateString() ?? now()->toDateString(),
                'method' => $voucher->kind === Voucher::KIND_CASH ? 'cash' : 'bank_transfer',
                'reference' => $reference,
                'notes' => "Paid through voucher {$voucher->number}",
                'allocations' => [['supplier_invoice_id' => $invoice->id, 'amount' => $amount]],
            ], $actor);
            $this->supplierPayments->post($supplierPayment, $actor);

            $payment->forceFill(['supplier_payment_id' => $supplierPayment->id])->save();

            return;
        }

        $entry = $this->journal->post([
            ['account_id' => $voucher->ledger_account_id, 'debit' => $amount, 'description' => "{$voucher->number}: {$voucher->purpose}"],
            ['account_id' => $from->id, 'credit' => $amount, 'description' => "{$voucher->number} paid to {$voucher->payee}"],
        ], "Voucher {$voucher->number} payment {$payment->sequence}", $payment->payment_date?->toDateString(), $payment, 'post', $actor);

        $payment->forceFill(['journal_entry_id' => $entry->id])->save();
    }

    /** The voucher in progress for a source document, if one is. */
    public function openVoucherFor(string $type, int $id): ?Voucher
    {
        return Voucher::query()
            ->where('source_type', $type)->where('source_id', $id)
            ->whereNotIn('status', [Voucher::STATUS_REJECTED, Voucher::STATUS_CANCELLED])
            ->where(fn ($q) => $q->whereNull('paid_at')->orWhere('status', '!=', Voucher::STATUS_PAID))
            ->latest('id')->first();
    }

    /** Cash vouchers pay from cash on hand, everything else from the bank. */
    private function payingAccount(Voucher $voucher, VoucherPayment $payment): Account
    {
        $cash = $voucher->kind === Voucher::KIND_CASH || str_contains(strtolower((string) $payment->payment_method), 'cash');
        $key = $cash ? 'cash' : 'bank';

        return Account::query()->where('system_key', $key)->first()
            ?? throw new RuntimeException("The chart of accounts has no '{$key}' account to pay from.");
    }
}
