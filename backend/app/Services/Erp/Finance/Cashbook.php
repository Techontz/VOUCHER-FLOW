<?php

namespace App\Services\Erp\Finance;

use App\Models\Erp\Account;
use App\Models\Erp\Finance\BankAccount;
use App\Models\Erp\Finance\CashbookEntry;
use App\Models\Erp\JournalEntry;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * General receipts and payments: money in or out that no sale or purchase
 * explains. A receipt posts Dr bank / Cr the chosen account, a payment
 * Dr the chosen account / Cr bank; once, and reversed rather than edited.
 */
class Cashbook
{
    public function __construct(
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly BankAccounts $banks,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function create(array $data, User $actor): CashbookEntry
    {
        return DB::transaction(function () use ($data, $actor) {
            $type = $data['type'];
            $entry = CashbookEntry::create([
                ...$this->fields($data),
                'type' => $type,
                'number' => $this->numbers->next(CashbookEntry::PREFIXES[$type]),
                'status' => CashbookEntry::STATUS_DRAFT,
                'created_by' => $actor->id,
            ]);
            $this->audit->log("finance.cashbook.{$type}.created", "Prepared {$type} {$entry->number}", $entry, actor: $actor);

            return $entry->load('bankAccount', 'account');
        });
    }

    /** @param  array<string, mixed>  $data */
    public function update(CashbookEntry $entry, array $data, User $actor): CashbookEntry
    {
        return DB::transaction(function () use ($entry, $data, $actor) {
            $locked = $this->lock($entry);
            $this->assertDraft($locked, 'edited');
            $locked->update($this->fields($data));
            $this->audit->log("finance.cashbook.{$locked->type}.updated", "Edited draft {$locked->number}", $locked, actor: $actor);

            return $locked->load('bankAccount', 'account');
        });
    }

    public function post(CashbookEntry $entry, User $actor): CashbookEntry
    {
        return DB::transaction(function () use ($entry, $actor) {
            $locked = $this->lock($entry);
            $this->assertDraft($locked, 'posted');

            $date = $locked->entry_date->toDateString();
            PeriodLock::assertOpen($date);

            $bank = $locked->bankAccount;
            $amount = round((float) $locked->amount, 2);

            if (! $bank->is_active) {
                throw new RuntimeException("{$bank->name} is closed.");
            }

            if ($locked->type === CashbookEntry::TYPE_PAYMENT) {
                $this->banks->assertCanPay($bank, $amount, $date);
            }

            $text = $locked->counterparty ? "{$locked->description} · {$locked->counterparty}" : $locked->description;
            $bankLine = ['account_id' => $bank->account_id, 'description' => $text];
            $otherLine = ['account_id' => $locked->account_id, 'description' => $text];

            $lines = $locked->type === CashbookEntry::TYPE_RECEIPT
                ? [[...$bankLine, 'debit' => $amount], [...$otherLine, 'credit' => $amount]]
                : [[...$otherLine, 'debit' => $amount], [...$bankLine, 'credit' => $amount]];

            $journal = $this->journal->post($lines, ucfirst($locked->type)." {$locked->number}: {$locked->description}", $date, $locked, 'post', $actor);

            $locked->update([
                'status' => CashbookEntry::STATUS_POSTED,
                'journal_entry_id' => $journal->id,
                'posted_by' => $actor->id,
                'posted_at' => now(),
            ]);
            $this->audit->log("finance.cashbook.{$locked->type}.posted", "Posted {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(['bankAccount', 'account', 'journal.lines.account']);
        });
    }

    public function reverse(CashbookEntry $entry, string $reason, User $actor): CashbookEntry
    {
        return DB::transaction(function () use ($entry, $reason, $actor) {
            $locked = $this->lock($entry);

            if ($locked->status !== CashbookEntry::STATUS_POSTED) {
                throw new RuntimeException("Only a posted entry can be reversed; {$locked->number} is {$locked->status}.");
            }

            PeriodLock::assertOpen(now()->toDateString());

            /** @var JournalEntry $journal */
            $journal = JournalEntry::query()->findOrFail($locked->journal_entry_id);
            $this->journal->reverse($journal, "{$locked->number} reversed: {$reason}", $actor);

            $locked->update([
                'status' => CashbookEntry::STATUS_REVERSED,
                'reversed_by' => $actor->id,
                'reversed_at' => now(),
                'reversal_reason' => mb_substr($reason, 0, 255),
            ]);
            $this->audit->log("finance.cashbook.{$locked->type}.reversed", "Reversed {$locked->number} · {$reason}", $locked, actor: $actor);

            return $locked->fresh(['bankAccount', 'account']);
        });
    }

    public function cancel(CashbookEntry $entry, User $actor): CashbookEntry
    {
        return DB::transaction(function () use ($entry, $actor) {
            $locked = $this->lock($entry);
            $this->assertDraft($locked, 'cancelled');
            $locked->update(['status' => CashbookEntry::STATUS_CANCELLED]);
            $this->audit->log("finance.cashbook.{$locked->type}.cancelled", "Cancelled draft {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    /** @return array<string, mixed> */
    private function fields(array $data): array
    {
        $bank = BankAccount::query()->findOrFail($data['bank_account_id']);
        $account = Account::query()->findOrFail($data['account_id']);

        if (! $bank->is_active) {
            throw new RuntimeException("{$bank->name} is closed.");
        }

        if (! $account->is_active) {
            throw new RuntimeException("{$account->code} {$account->name} is inactive.");
        }

        if (Ledger::isCashAccount($account)) {
            throw new RuntimeException("{$account->code} {$account->name} is a cash or bank account: use a bank transfer to move money between your own accounts.");
        }

        return [
            'entry_date' => $data['entry_date'] ?? now()->toDateString(),
            'bank_account_id' => $bank->id,
            'account_id' => $account->id,
            'amount' => $data['amount'],
            'counterparty' => $data['counterparty'] ?? null,
            'reference' => $data['reference'] ?? null,
            'description' => $data['description'],
        ];
    }

    private function lock(CashbookEntry $entry): CashbookEntry
    {
        return CashbookEntry::query()->whereKey($entry->id)->lockForUpdate()->firstOrFail();
    }

    private function assertDraft(CashbookEntry $entry, string $verb): void
    {
        if ($entry->status !== CashbookEntry::STATUS_DRAFT) {
            throw new RuntimeException("{$entry->number} is {$entry->status} and cannot be {$verb}.");
        }
    }
}
