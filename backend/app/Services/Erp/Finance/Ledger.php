<?php

namespace App\Services\Erp\Finance;

use App\Models\Erp\Account;
use App\Support\TenantContext;
use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Reads the journal for the finance screens. Every figure here comes from
 * journal lines, the source of truth, scoped to the caller's company.
 */
class Ledger
{
    /** The source type of the year-end closing entry, left out of profit and loss. */
    public const CLOSING_SOURCE = 'YearEndClosing';

    public function __construct(private readonly TenantContext $tenant) {}

    /** Cash and bank accounts: asset accounts numbered 1100 to 1299. */
    public static function isCashAccount(Account $account): bool
    {
        return $account->type === 'asset' && ctype_digit((string) $account->code)
            && (int) $account->code >= 1100 && (int) $account->code <= 1299;
    }

    /** @return list<int> */
    public function cashAccountIds(): array
    {
        return Account::query()->where('type', 'asset')->get()
            ->filter(fn (Account $a) => self::isCashAccount($a))
            ->pluck('id')->map(fn ($id) => (int) $id)->values()->all();
    }

    /** Journal lines joined to their entries, for this company. */
    public function lines(?string $from = null, ?string $to = null, bool $withClosing = true): Builder
    {
        return DB::table('journal_lines')
            ->join('journal_entries', 'journal_entries.id', '=', 'journal_lines.journal_entry_id')
            ->where('journal_entries.company_id', $this->tenant->id())
            ->when($from, fn ($q) => $q->where('journal_entries.entry_date', '>=', $from))
            ->when($to, fn ($q) => $q->where('journal_entries.entry_date', '<=', $to))
            ->when(! $withClosing, fn ($q) => $q->where(fn ($w) => $w
                ->whereNull('journal_entries.source_type')
                ->orWhere('journal_entries.source_type', '!=', self::CLOSING_SOURCE)));
    }

    /**
     * Debit and credit totals per account id.
     *
     * @return array<int, array{debit: float, credit: float}>
     */
    public function totals(?string $from = null, ?string $to = null, bool $withClosing = true): array
    {
        return $this->lines($from, $to, $withClosing)
            ->groupBy('journal_lines.account_id')
            ->selectRaw('journal_lines.account_id, SUM(journal_lines.debit) AS debit, SUM(journal_lines.credit) AS credit')
            ->get()
            ->mapWithKeys(fn ($r) => [(int) $r->account_id => ['debit' => round((float) $r->debit, 2), 'credit' => round((float) $r->credit, 2)]])
            ->all();
    }

    /** Debits less credits on one account up to a date. */
    public function balance(int $accountId, ?string $to = null, ?string $from = null): float
    {
        $row = $this->lines($from, $to)->where('journal_lines.account_id', $accountId)
            ->selectRaw('COALESCE(SUM(journal_lines.debit), 0) AS debit, COALESCE(SUM(journal_lines.credit), 0) AS credit')
            ->first();

        return round((float) $row->debit - (float) $row->credit, 2);
    }

    /**
     * Debits less credits per account, for a set of accounts.
     *
     * @param  list<int>  $accountIds
     * @return array<int, float>
     */
    public function balances(array $accountIds, ?string $to = null): array
    {
        if (! $accountIds) {
            return [];
        }

        return $this->lines(null, $to)->whereIn('journal_lines.account_id', $accountIds)
            ->groupBy('journal_lines.account_id')
            ->selectRaw('journal_lines.account_id, SUM(journal_lines.debit) - SUM(journal_lines.credit) AS net')
            ->pluck('net', 'account_id')
            ->map(fn ($v) => round((float) $v, 2))
            ->all();
    }
}
