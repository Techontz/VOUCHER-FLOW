<?php

namespace App\Services\Erp\Finance;

use App\Models\Erp\Finance\BankAccount;
use App\Models\Erp\Finance\BankReconciliation;
use App\Models\Erp\Finance\BankStatementLine;
use App\Models\Erp\Finance\CashbookEntry;
use App\Models\Erp\JournalLine;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use Throwable;

/**
 * Bank reconciliation: the bank's statement against the books.
 *
 * Each statement line is matched to one journal line on the bank's ledger
 * account, for the same amount; a journal line can be matched once, ever.
 * The arithmetic is the textbook one:
 *
 *   adjusted bank = statement closing + deposits not yet on a statement
 *                                      - payments not yet on a statement
 *   adjusted book = book balance + statement lines not yet in the books
 *
 * and a reconciliation completes only when every statement line is matched
 * and the two agree to the cent. A bank account's opening balance entry is
 * treated as already cleared: it is the balance the first statement opens on.
 */
class Reconciliations
{
    /** Days either side of a statement line a suggested match may fall. */
    public const MATCH_WINDOW_DAYS = 7;

    public function __construct(
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly Ledger $ledger,
        private readonly Cashbook $cashbook,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function start(BankAccount $bank, array $data, User $actor): BankReconciliation
    {
        return DB::transaction(function () use ($bank, $data, $actor) {
            BankAccount::query()->whereKey($bank->id)->lockForUpdate()->first();

            if (BankReconciliation::query()->where('bank_account_id', $bank->id)->where('status', BankReconciliation::STATUS_OPEN)->exists()) {
                throw new RuntimeException("{$bank->name} already has a reconciliation in progress. Complete or delete it first.");
            }

            $last = BankReconciliation::query()->where('bank_account_id', $bank->id)
                ->where('status', BankReconciliation::STATUS_COMPLETED)->latest('statement_date')->first();

            if ($last && $last->statement_date->toDateString() >= $data['statement_date']) {
                throw new RuntimeException("{$bank->name} is already reconciled to {$last->statement_date->format('j M Y')}; choose a later statement date.");
            }

            $reconciliation = BankReconciliation::create([
                'bank_account_id' => $bank->id,
                'number' => $this->numbers->next('BRC'),
                'statement_date' => $data['statement_date'],
                'statement_opening_balance' => $data['statement_opening_balance'] ?? ($last?->statement_closing_balance ?? $bank->opening_balance),
                'statement_closing_balance' => $data['statement_closing_balance'],
                'notes' => $data['notes'] ?? null,
                'status' => BankReconciliation::STATUS_OPEN,
                'created_by' => $actor->id,
            ]);
            $this->audit->log('finance.reconciliation.started', "Started reconciliation {$reconciliation->number} for {$bank->name}", $reconciliation, actor: $actor);

            return $reconciliation;
        });
    }

    /** @param  array<string, mixed>  $data */
    public function update(BankReconciliation $reconciliation, array $data, User $actor): BankReconciliation
    {
        $this->assertOpen($reconciliation);
        $reconciliation->update(collect($data)->only(['statement_date', 'statement_opening_balance', 'statement_closing_balance', 'notes'])->all());
        $this->audit->log('finance.reconciliation.updated', "Updated statement balances on {$reconciliation->number}", $reconciliation, actor: $actor);

        return $reconciliation;
    }

    public function delete(BankReconciliation $reconciliation, User $actor): void
    {
        $this->assertOpen($reconciliation);
        DB::transaction(function () use ($reconciliation, $actor) {
            $reconciliation->lines()->delete();
            $reconciliation->delete();
            $this->audit->log('finance.reconciliation.deleted', "Deleted reconciliation {$reconciliation->number}", $reconciliation, actor: $actor);
        });
    }

    /**
     * @param  list<array{line_date: string, description: string, amount: float|string, reference?: ?string}>  $lines
     * @return Collection<int, BankStatementLine>
     */
    public function addLines(BankReconciliation $reconciliation, array $lines, User $actor): Collection
    {
        $this->assertOpen($reconciliation);

        return DB::transaction(function () use ($reconciliation, $lines, $actor) {
            $created = collect($lines)->map(function (array $line) use ($reconciliation) {
                if (round((float) $line['amount'], 2) == 0.0) {
                    throw new RuntimeException("A statement line needs an amount: '{$line['description']}' has none.");
                }

                return $reconciliation->lines()->create([
                    'company_id' => $reconciliation->company_id,
                    'line_date' => $line['line_date'],
                    'description' => mb_substr((string) $line['description'], 0, 255),
                    'reference' => isset($line['reference']) ? mb_substr((string) $line['reference'], 0, 80) : null,
                    'amount' => round((float) $line['amount'], 2),
                ]);
            });

            $this->audit->log('finance.reconciliation.lines_added', "Added {$created->count()} statement line(s) to {$reconciliation->number}", $reconciliation, actor: $actor);

            return $created;
        });
    }

    /**
     * Reads a statement CSV with a header row naming date, description,
     * amount and reference (amount may instead be two columns, money in and
     * money out). Every row must read cleanly or nothing is imported.
     *
     * @return list<array{line_date: string, description: string, amount: float, reference: ?string}>
     */
    public function parseCsv(string $contents): array
    {
        $rows = array_values(array_filter(
            array_map(fn ($line) => str_getcsv($line, ',', '"', ''), preg_split('/\r\n|\n|\r/', trim($contents)) ?: []),
            fn ($row) => count(array_filter($row, fn ($c) => trim((string) $c) !== '')) > 0,
        ));

        if (count($rows) < 2) {
            throw new RuntimeException('The file needs a header row and at least one line.');
        }

        $header = array_map(fn ($h) => strtolower(trim(preg_replace('/^\xEF\xBB\xBF/', '', (string) $h))), $rows[0]);
        $find = function (array $names) use ($header): ?int {
            foreach ($names as $name) {
                $i = array_search($name, $header, true);
                if ($i !== false) {
                    return $i;
                }
            }

            return null;
        };

        $date = $find(['date', 'transaction date', 'value date', 'posting date']);
        $description = $find(['description', 'details', 'narration', 'particulars']);
        $amount = $find(['amount']);
        $in = $find(['money in', 'credit', 'deposit', 'deposits', 'paid in']);
        $out = $find(['money out', 'debit', 'withdrawal', 'withdrawals', 'paid out']);
        $reference = $find(['reference', 'ref', 'cheque no', 'transaction id']);

        if ($date === null || $description === null || ($amount === null && ($in === null || $out === null))) {
            throw new RuntimeException('The header row must name date, description and amount (or money in and money out) columns.');
        }

        $lines = [];

        foreach (array_slice($rows, 1) as $i => $row) {
            $number = $i + 2;
            $value = fn (?int $col) => $col === null ? '' : trim((string) ($row[$col] ?? ''));
            $parsedDate = $this->parseDate($value($date));

            if (! $parsedDate) {
                throw new RuntimeException("Row {$number}: '{$value($date)}' is not a date (use YYYY-MM-DD or DD/MM/YYYY).");
            }

            $money = fn (string $v) => $v === '' ? 0.0 : (float) str_replace([',', ' '], '', $v);
            $signed = $amount !== null ? $money($value($amount)) : $money($value($in)) - abs($money($value($out)));

            if ($amount !== null && ! is_numeric(str_replace([',', ' '], '', $value($amount)))) {
                throw new RuntimeException("Row {$number}: '{$value($amount)}' is not an amount.");
            }

            if (round($signed, 2) == 0.0) {
                throw new RuntimeException("Row {$number}: the amount is zero.");
            }

            $lines[] = [
                'line_date' => $parsedDate,
                'description' => $value($description) ?: 'Statement line',
                'amount' => round($signed, 2),
                'reference' => $value($reference) ?: null,
            ];
        }

        return $lines;
    }

    public function deleteLine(BankStatementLine $line, User $actor): void
    {
        $this->assertOpen($line->reconciliation);

        if ($line->journal_line_id) {
            throw new RuntimeException('Unmatch this line before deleting it.');
        }

        $line->delete();
        $this->audit->log('finance.reconciliation.line_deleted', "Deleted statement line {$line->description}", $line->reconciliation, actor: $actor);
    }

    public function match(BankStatementLine $line, int $journalLineId, User $actor): BankStatementLine
    {
        return DB::transaction(function () use ($line, $journalLineId, $actor) {
            /** @var BankStatementLine $locked */
            $locked = BankStatementLine::query()->whereKey($line->id)->lockForUpdate()->firstOrFail();
            $reconciliation = $locked->reconciliation;
            $this->assertOpen($reconciliation);

            if ($locked->journal_line_id) {
                throw new RuntimeException('This statement line is already matched.');
            }

            $candidate = $this->bookLines($reconciliation)->where('journal_lines.id', $journalLineId)->first();

            if (! $candidate) {
                throw new RuntimeException('That ledger line is not an unreconciled item on this bank account up to the statement date.');
            }

            $bookAmount = round((float) $candidate->debit - (float) $candidate->credit, 2);

            if (abs($bookAmount - (float) $locked->amount) >= 0.005) {
                throw new RuntimeException(sprintf('The amounts differ: the statement shows %s and the books %s.', number_format((float) $locked->amount, 2), number_format($bookAmount, 2)));
            }

            $locked->update(['journal_line_id' => $journalLineId, 'matched_by' => $actor->id, 'matched_at' => now()]);
            $this->audit->log('finance.reconciliation.matched', "Matched '{$locked->description}' on {$reconciliation->number}", $reconciliation, actor: $actor);

            return $locked;
        });
    }

    public function unmatch(BankStatementLine $line, User $actor): BankStatementLine
    {
        $this->assertOpen($line->reconciliation);
        $line->update(['journal_line_id' => null, 'matched_by' => null, 'matched_at' => null]);
        $this->audit->log('finance.reconciliation.unmatched', "Unmatched '{$line->description}'", $line->reconciliation, actor: $actor);

        return $line;
    }

    /** Matches every statement line that has exactly one best candidate: same amount, nearest date. */
    public function autoMatch(BankReconciliation $reconciliation, User $actor): int
    {
        $this->assertOpen($reconciliation);

        return DB::transaction(function () use ($reconciliation, $actor) {
            $candidates = $this->bookLines($reconciliation)->get();
            $used = [];
            $matched = 0;

            foreach ($reconciliation->lines()->whereNull('journal_line_id')->orderBy('line_date')->get() as $line) {
                $best = $this->rank($line, $candidates->reject(fn ($c) => isset($used[$c->id])))->first();

                if ($best) {
                    $used[$best['journal_line_id']] = true;
                    $line->update(['journal_line_id' => $best['journal_line_id'], 'matched_by' => $actor->id, 'matched_at' => now()]);
                    $matched++;
                }
            }

            if ($matched) {
                $this->audit->log('finance.reconciliation.auto_matched', "Auto-matched {$matched} line(s) on {$reconciliation->number}", $reconciliation, actor: $actor);
            }

            return $matched;
        });
    }

    /**
     * Books a statement line the books do not have yet (bank charges,
     * interest) as a posted cashbook entry against the chosen account, and
     * matches it.
     */
    public function createEntry(BankStatementLine $line, int $accountId, User $actor): BankStatementLine
    {
        return DB::transaction(function () use ($line, $accountId, $actor) {
            $reconciliation = $line->reconciliation;
            $this->assertOpen($reconciliation);

            if ($line->journal_line_id) {
                throw new RuntimeException('This statement line is already matched.');
            }

            $amount = (float) $line->amount;
            $entry = $this->cashbook->create([
                'type' => $amount > 0 ? CashbookEntry::TYPE_RECEIPT : CashbookEntry::TYPE_PAYMENT,
                'entry_date' => $line->line_date->toDateString(),
                'bank_account_id' => $reconciliation->bank_account_id,
                'account_id' => $accountId,
                'amount' => abs($amount),
                'reference' => $line->reference,
                'description' => $line->description,
                'counterparty' => $reconciliation->bankAccount->bank_name,
            ], $actor);
            $posted = $this->cashbook->post($entry, $actor);

            $bankLine = JournalLine::query()->where('journal_entry_id', $posted->journal_entry_id)
                ->where('account_id', $reconciliation->bankAccount->account_id)->firstOrFail();

            return $this->match($line, $bankLine->id, $actor);
        });
    }

    public function complete(BankReconciliation $reconciliation, User $actor): BankReconciliation
    {
        return DB::transaction(function () use ($reconciliation, $actor) {
            /** @var BankReconciliation $locked */
            $locked = BankReconciliation::query()->whereKey($reconciliation->id)->lockForUpdate()->firstOrFail();
            $this->assertOpen($locked);
            $summary = $this->summary($locked);

            if ($summary['unmatched_statement_count'] > 0) {
                throw new RuntimeException("{$summary['unmatched_statement_count']} statement line(s) are not matched yet. Match them, or book them with Create entry.");
            }

            if (abs($summary['statement_lines_difference']) >= 0.005) {
                throw new RuntimeException(sprintf('The statement lines add up to %s, but opening %s and closing %s differ by %s. A line is missing or mistyped.',
                    number_format($summary['statement_lines_total'], 2), number_format((float) $locked->statement_opening_balance, 2),
                    number_format((float) $locked->statement_closing_balance, 2), number_format((float) $locked->statement_closing_balance - (float) $locked->statement_opening_balance, 2)));
            }

            if (abs($summary['difference']) >= 0.005) {
                throw new RuntimeException('The adjusted bank balance and the adjusted book balance differ by '.number_format($summary['difference'], 2).'.');
            }

            $locked->update(['status' => BankReconciliation::STATUS_COMPLETED, 'completed_by' => $actor->id, 'completed_at' => now()]);
            $this->audit->log('finance.reconciliation.completed', "Completed reconciliation {$locked->number}", $locked, actor: $actor);

            return $locked;
        });
    }

    /** @return array<string, mixed> */
    public function summary(BankReconciliation $reconciliation): array
    {
        $bank = $reconciliation->bankAccount;
        $date = $reconciliation->statement_date->toDateString();
        $lines = $reconciliation->lines()->get();

        $bookBalance = $this->ledger->balance($bank->account_id, $date);
        $outstanding = $this->bookLines($reconciliation)->get();
        $depositsInTransit = round($outstanding->sum(fn ($l) => (float) $l->debit), 2);
        $outstandingPayments = round($outstanding->sum(fn ($l) => (float) $l->credit), 2);

        $unmatched = $lines->whereNull('journal_line_id');
        $unmatchedTotal = round($unmatched->sum(fn ($l) => (float) $l->amount), 2);
        $linesTotal = round($lines->sum(fn ($l) => (float) $l->amount), 2);

        $closing = (float) $reconciliation->statement_closing_balance;
        $adjustedBank = round($closing + $depositsInTransit - $outstandingPayments, 2);
        $adjustedBook = round($bookBalance + $unmatchedTotal, 2);

        return [
            'book_balance' => $bookBalance,
            'cleared_balance' => round($bookBalance - $depositsInTransit + $outstandingPayments, 2),
            'statement_opening_balance' => (float) $reconciliation->statement_opening_balance,
            'statement_closing_balance' => $closing,
            'statement_lines_total' => $linesTotal,
            'statement_lines_difference' => round((float) $reconciliation->statement_opening_balance + $linesTotal - $closing, 2),
            'matched_count' => $lines->whereNotNull('journal_line_id')->count(),
            'unmatched_statement_count' => $unmatched->count(),
            'unmatched_statement_total' => $unmatchedTotal,
            'deposits_in_transit' => $depositsInTransit,
            'outstanding_payments' => $outstandingPayments,
            'adjusted_bank_balance' => $adjustedBank,
            'adjusted_book_balance' => $adjustedBook,
            'difference' => round($adjustedBank - $adjustedBook, 2),
        ];
    }

    /**
     * Unreconciled ledger items on the bank account up to the statement
     * date, with the statement lines each could match.
     *
     * @return Collection<int, object>
     */
    public function outstanding(BankReconciliation $reconciliation): Collection
    {
        return $this->bookLines($reconciliation)->orderBy('journal_entries.entry_date')->orderBy('journal_lines.id')->get();
    }

    /** @return Collection<int, array{journal_line_id: int, entry_date: string, number: string, memo: string, amount: float, days: int}> */
    public function suggestions(BankStatementLine $line): Collection
    {
        return $this->rank($line, $this->bookLines($line->reconciliation)->get())->take(5)->values();
    }

    /**
     * Candidates for a statement line: the same signed amount, within the
     * window, nearest date first.
     *
     * @param  Collection<int, object>  $candidates
     * @return Collection<int, array<string, mixed>>
     */
    private function rank(BankStatementLine $line, Collection $candidates): Collection
    {
        $amount = round((float) $line->amount, 2);
        $day = CarbonImmutable::parse($line->line_date);

        return $candidates
            ->filter(fn ($c) => abs(round((float) $c->debit - (float) $c->credit, 2) - $amount) < 0.005)
            ->map(fn ($c) => [
                'journal_line_id' => (int) $c->id,
                'entry_date' => $c->entry_date,
                'number' => $c->number,
                'memo' => $c->memo,
                'description' => $c->description,
                'amount' => round((float) $c->debit - (float) $c->credit, 2),
                'days' => (int) abs($day->diffInDays(CarbonImmutable::parse($c->entry_date))),
            ])
            ->filter(fn ($c) => $c['days'] <= self::MATCH_WINDOW_DAYS)
            ->sortBy('days')
            ->values();
    }

    /** Ledger lines on the bank's account to the statement date that no statement line holds. */
    private function bookLines(BankReconciliation $reconciliation)
    {
        $bank = $reconciliation->bankAccount;

        return $this->ledger->lines(null, $reconciliation->statement_date->toDateString())
            ->where('journal_lines.account_id', $bank->account_id)
            ->whereNotExists(fn ($q) => $q->from('bank_statement_lines')->whereColumn('bank_statement_lines.journal_line_id', 'journal_lines.id'))
            ->when($bank->opening_entry_id, fn ($q) => $q->where('journal_entries.id', '!=', $bank->opening_entry_id))
            ->select('journal_lines.id', 'journal_lines.debit', 'journal_lines.credit', 'journal_lines.description',
                'journal_entries.entry_date', 'journal_entries.number', 'journal_entries.memo');
    }

    private function parseDate(string $value): ?string
    {
        foreach (['Y-m-d', 'd/m/Y', 'd-m-Y', 'd.m.Y', 'j/n/Y', 'Y/m/d'] as $format) {
            try {
                $date = CarbonImmutable::createFromFormat('!'.$format, $value);
                if ($date && $date->format($format) === $value) {
                    return $date->toDateString();
                }
            } catch (Throwable) {
                // try the next format
            }
        }

        return null;
    }

    private function assertOpen(BankReconciliation $reconciliation): void
    {
        if (! $reconciliation->isOpen()) {
            throw new RuntimeException("{$reconciliation->number} is completed and can no longer change.");
        }
    }
}
