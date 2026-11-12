<?php

namespace App\Services\Erp\Finance;

use App\Models\Erp\Finance\BankAccount;
use App\Models\Erp\Finance\BankTransfer;
use App\Models\Erp\JournalEntry;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Transfers between the company's own accounts. A draft changes nothing;
 * posting writes Dr destination / Cr source (and Dr bank charges / Cr source
 * for the bank's fee) once, under a row lock; a mistake is reversed.
 */
class BankTransfers
{
    public function __construct(
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly BankAccounts $banks,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function create(array $data, User $actor): BankTransfer
    {
        return DB::transaction(function () use ($data, $actor) {
            $transfer = BankTransfer::create([
                ...$this->fields($data),
                'number' => $this->numbers->next('BTF'),
                'status' => BankTransfer::STATUS_DRAFT,
                'created_by' => $actor->id,
            ]);
            $this->audit->log('finance.transfer.created', "Prepared transfer {$transfer->number}", $transfer, actor: $actor);

            return $transfer->load('from', 'to');
        });
    }

    /** @param  array<string, mixed>  $data */
    public function update(BankTransfer $transfer, array $data, User $actor): BankTransfer
    {
        return DB::transaction(function () use ($transfer, $data, $actor) {
            $locked = $this->lock($transfer);
            $this->assertDraft($locked, 'edited');
            $locked->update($this->fields($data));
            $this->audit->log('finance.transfer.updated', "Edited draft transfer {$locked->number}", $locked, actor: $actor);

            return $locked->load('from', 'to');
        });
    }

    public function post(BankTransfer $transfer, User $actor): BankTransfer
    {
        return DB::transaction(function () use ($transfer, $actor) {
            $locked = $this->lock($transfer);
            $this->assertDraft($locked, 'posted');

            $date = $locked->transfer_date->toDateString();
            PeriodLock::assertOpen($date);

            $from = $locked->from;
            $to = $locked->to;
            $amount = round((float) $locked->amount, 2);
            $charges = round((float) $locked->charges, 2);

            if (! $from->is_active || ! $to->is_active) {
                throw new RuntimeException('Both accounts must be active to post a transfer.');
            }

            $this->banks->assertCanPay($from, $amount + $charges, $date);

            $lines = [
                ['account_id' => $to->account_id, 'debit' => $amount, 'description' => "From {$from->name}"],
                ['account_id' => $from->account_id, 'credit' => round($amount + $charges, 2), 'description' => "To {$to->name}"],
            ];

            if ($charges > 0) {
                $lines[] = ['account' => 'bank_charges', 'debit' => $charges, 'description' => "Charges on {$locked->number}"];
            }

            $entry = $this->journal->post($lines, "Transfer {$locked->number}: {$from->name} to {$to->name}", $date, $locked, 'post', $actor);

            $locked->update([
                'status' => BankTransfer::STATUS_POSTED,
                'journal_entry_id' => $entry->id,
                'posted_by' => $actor->id,
                'posted_at' => now(),
            ]);
            $this->audit->log('finance.transfer.posted', "Posted transfer {$locked->number}", $locked, actor: $actor);

            return $locked->fresh(['from', 'to', 'journal.lines.account']);
        });
    }

    public function reverse(BankTransfer $transfer, string $reason, User $actor): BankTransfer
    {
        return DB::transaction(function () use ($transfer, $reason, $actor) {
            $locked = $this->lock($transfer);

            if ($locked->status !== BankTransfer::STATUS_POSTED) {
                throw new RuntimeException("Only a posted transfer can be reversed; {$locked->number} is {$locked->status}.");
            }

            PeriodLock::assertOpen(now()->toDateString());

            /** @var JournalEntry $entry */
            $entry = JournalEntry::query()->findOrFail($locked->journal_entry_id);
            $this->journal->reverse($entry, "Transfer {$locked->number} reversed: {$reason}", $actor);

            $locked->update([
                'status' => BankTransfer::STATUS_REVERSED,
                'reversed_by' => $actor->id,
                'reversed_at' => now(),
                'reversal_reason' => mb_substr($reason, 0, 255),
            ]);
            $this->audit->log('finance.transfer.reversed', "Reversed transfer {$locked->number} · {$reason}", $locked, actor: $actor);

            return $locked->fresh(['from', 'to']);
        });
    }

    public function cancel(BankTransfer $transfer, User $actor): BankTransfer
    {
        return DB::transaction(function () use ($transfer, $actor) {
            $locked = $this->lock($transfer);
            $this->assertDraft($locked, 'cancelled');
            $locked->update(['status' => BankTransfer::STATUS_CANCELLED]);
            $this->audit->log('finance.transfer.cancelled', "Cancelled draft transfer {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    /** @return array<string, mixed> */
    private function fields(array $data): array
    {
        $from = BankAccount::query()->findOrFail($data['from_bank_account_id']);
        $to = BankAccount::query()->findOrFail($data['to_bank_account_id']);

        if ($from->id === $to->id) {
            throw new RuntimeException('Choose two different accounts to transfer between.');
        }

        if (! $from->is_active || ! $to->is_active) {
            throw new RuntimeException('Both accounts must be active.');
        }

        if ($from->currency !== $to->currency) {
            throw new RuntimeException("{$from->name} is in {$from->currency} and {$to->name} in {$to->currency}; transfers between currencies are not supported yet.");
        }

        return [
            'transfer_date' => $data['transfer_date'] ?? now()->toDateString(),
            'from_bank_account_id' => $from->id,
            'to_bank_account_id' => $to->id,
            'amount' => $data['amount'],
            'charges' => $data['charges'] ?? 0,
            'reference' => $data['reference'] ?? null,
            'memo' => $data['memo'] ?? null,
        ];
    }

    private function lock(BankTransfer $transfer): BankTransfer
    {
        return BankTransfer::query()->whereKey($transfer->id)->lockForUpdate()->firstOrFail();
    }

    private function assertDraft(BankTransfer $transfer, string $verb): void
    {
        if ($transfer->status !== BankTransfer::STATUS_DRAFT) {
            throw new RuntimeException("{$transfer->number} is {$transfer->status} and cannot be {$verb}.");
        }
    }
}
