<?php

namespace App\Services\Erp\Finance;

use App\Models\Erp\Account;
use App\Models\Erp\Finance\BankAccount;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\JournalPoster;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Registers bank, mobile money and cash accounts. Each gets its own ledger
 * account in 1201-1299 so every other module can receive or pay through it
 * by account id, and an opening balance posted once (Dr bank / Cr opening
 * balance equity).
 */
class BankAccounts
{
    public const FIRST_CODE = 1201;

    public const LAST_CODE = 1299;

    public function __construct(
        private readonly JournalPoster $journal,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
        private readonly Ledger $ledger,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function create(array $data, User $actor): BankAccount
    {
        return DB::transaction(function () use ($data, $actor) {
            $code = $this->code($data['code'] ?? null);

            $account = Account::create([
                'company_id' => $this->tenant->id(),
                'code' => (string) $code,
                'name' => $data['name'],
                'type' => 'asset',
                'parent_id' => Account::query()->where('system_key', 'bank')->value('id'),
            ]);

            $bank = BankAccount::create([
                'account_id' => $account->id,
                'name' => $data['name'],
                'type' => $data['type'] ?? 'bank',
                'bank_name' => $data['bank_name'] ?? null,
                'branch' => $data['branch'] ?? null,
                'account_name' => $data['account_name'] ?? null,
                'account_number' => $data['account_number'] ?? null,
                'currency' => $data['currency'] ?? 'TZS',
                'opening_balance' => $data['opening_balance'] ?? 0,
                'opening_date' => $data['opening_date'] ?? now()->toDateString(),
                'notes' => $data['notes'] ?? null,
                'created_by' => $actor->id,
            ]);

            $this->postOpening($bank, $actor);
            $this->audit->log('finance.bank_account.created', "Added bank account {$bank->name} ({$code})", $bank, actor: $actor);

            return $bank->fresh(['account']);
        });
    }

    /** @param  array<string, mixed>  $data */
    public function update(BankAccount $bank, array $data, User $actor): BankAccount
    {
        return DB::transaction(function () use ($bank, $data, $actor) {
            if (array_key_exists('is_active', $data) && ! $data['is_active'] && $bank->is_active) {
                $balance = $this->ledger->balance($bank->account_id);
                if (abs($balance) >= 0.005) {
                    throw new RuntimeException("{$bank->name} still holds ".number_format($balance, 2).'. Move the balance out before closing the account.');
                }
            }

            $before = $bank->only(['name', 'bank_name', 'branch', 'account_name', 'account_number', 'is_active']);
            $bank->update(collect($data)->only(['name', 'type', 'bank_name', 'branch', 'account_name', 'account_number', 'currency', 'is_active', 'notes'])->all());

            if (isset($data['name'])) {
                $bank->account()->update(['name' => $data['name']]);
            }

            $this->audit->log('finance.bank_account.updated', "Updated bank account {$bank->name}", $bank,
                $before, $bank->only(array_keys($before)), actor: $actor);

            return $bank->fresh(['account']);
        });
    }

    /**
     * Cash and mobile money cannot go below zero; a bank may run an overdraft.
     */
    public function assertCanPay(BankAccount $bank, float $amount, string $date): void
    {
        if ($bank->type === 'bank') {
            return;
        }

        // Locked so two payments cannot both spend the same cash.
        BankAccount::query()->whereKey($bank->id)->lockForUpdate()->first();
        $available = $this->ledger->balance($bank->account_id);

        if ($available + 0.005 < $amount) {
            throw new RuntimeException(sprintf('%s holds %s; it cannot pay out %s.', $bank->name, number_format($available, 2), number_format($amount, 2)));
        }
    }

    private function postOpening(BankAccount $bank, User $actor): void
    {
        $amount = round((float) $bank->opening_balance, 2);

        if (abs($amount) < 0.005 || ! BusinessConfig::of($this->tenant->company())->postsToLedger()) {
            return;
        }

        $date = $bank->opening_date->toDateString();
        PeriodLock::assertOpen($date);

        $lines = $amount > 0
            ? [['account_id' => $bank->account_id, 'debit' => $amount], ['account' => 'opening_equity', 'credit' => $amount]]
            : [['account' => 'opening_equity', 'debit' => -$amount], ['account_id' => $bank->account_id, 'credit' => -$amount]];

        $entry = $this->journal->post($lines, "Opening balance {$bank->name}", $date, $bank, 'opening', $actor);
        $bank->forceFill(['opening_entry_id' => $entry->id])->save();
    }

    /** The requested ledger code if free, else the next free one: 1210, 1220 ... then any gap. */
    private function code(mixed $requested): int
    {
        $taken = Account::query()->pluck('code')->filter(fn ($c) => ctype_digit((string) $c))->map(fn ($c) => (int) $c)->all();

        if ($requested !== null && $requested !== '') {
            $code = (int) $requested;
            if ($code < self::FIRST_CODE || $code > self::LAST_CODE) {
                throw new RuntimeException('A bank account\'s ledger code must be between '.self::FIRST_CODE.' and '.self::LAST_CODE.'.');
            }
            if (in_array($code, $taken, true)) {
                throw new RuntimeException("Ledger code {$code} is already in use.");
            }

            return $code;
        }

        $candidates = [...range(1210, 1290, 10), ...range(self::FIRST_CODE, self::LAST_CODE)];

        foreach ($candidates as $code) {
            if (! in_array($code, $taken, true)) {
                return $code;
            }
        }

        throw new RuntimeException('Every ledger code from 1201 to 1299 is in use; deactivate an old bank account first.');
    }
}
