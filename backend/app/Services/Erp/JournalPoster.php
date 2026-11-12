<?php

namespace App\Services\Erp;

use App\Models\Erp\Account;
use App\Models\Erp\JournalEntry;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\Finance\PeriodLock;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * The only way anything reaches the general ledger.
 *
 * Every entry is checked before it is written: at least two lines, each line
 * one-sided and positive, every account the company's own and active, and
 * debits equal to credits to the cent. An entry tied to a source document can
 * be posted once per purpose, asked twice, the second call is refused, and
 * the database's unique key refuses it again if two requests race.
 */
class JournalPoster
{
    public function __construct(
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
    ) {}

    /**
     * Each line names an account by id, or by `account`, a system key such as
     * 'inventory' or 'grni' that is resolved within the caller's company.
     *
     * @param  list<array{account_id?: int, account?: string, debit?: float|string|null, credit?: float|string|null, description?: ?string}>  $lines
     */
    public function post(
        array $lines,
        string $memo,
        ?string $date = null,
        ?Model $source = null,
        string $purpose = 'post',
        ?User $actor = null,
        ?int $reversalOfId = null,
    ): JournalEntry {
        $actor ??= auth()->user();
        $resolved = $this->validate($lines);
        // Nothing may post into a month finance has closed (the year-end
        // closing entry is the one exemption, and it asks for it explicitly).
        PeriodLock::assertOpen($date ?? now()->toDateString());

        if ($source && $this->existing($source, $purpose)) {
            throw new RuntimeException("{$this->describe($source)} has already been posted to the ledger.");
        }

        try {
            return DB::transaction(function () use ($resolved, $memo, $date, $source, $purpose, $actor, $reversalOfId) {
                $total = array_sum(array_column($resolved, 'debit_cents')) / 100;

                $entry = JournalEntry::create([
                    'number' => $this->numbers->next('JE'),
                    'entry_date' => $date ?? now()->toDateString(),
                    'memo' => mb_substr($memo, 0, 255),
                    'source_type' => $source ? class_basename($source) : null,
                    'source_id' => $source?->getKey(),
                    'purpose' => $purpose,
                    'status' => JournalEntry::STATUS_POSTED,
                    'total' => $total,
                    'reversal_of_id' => $reversalOfId,
                    'created_by' => $actor?->id,
                    'approved_by' => $actor?->id,
                    'posted_at' => now(),
                ]);

                foreach ($resolved as $line) {
                    $entry->lines()->create([
                        'account_id' => $line['account_id'],
                        'debit' => $line['debit_cents'] / 100,
                        'credit' => $line['credit_cents'] / 100,
                        'description' => $line['description'],
                    ]);
                }

                $this->audit->log('journal.posted', "Posted journal {$entry->number} · {$memo}", $entry, actor: $actor);

                return $entry->load('lines.account');
            });
        } catch (UniqueConstraintViolationException) {
            throw new RuntimeException($source
                ? "{$this->describe($source)} has already been posted to the ledger."
                : 'This journal entry could not be numbered; please try again.');
        }
    }

    /** Posts the mirror image of an entry and marks the original reversed. */
    public function reverse(JournalEntry $entry, string $reason, ?User $actor = null, ?string $date = null): JournalEntry
    {
        return DB::transaction(function () use ($entry, $reason, $actor, $date) {
            /** @var JournalEntry $locked */
            $locked = JournalEntry::query()->whereKey($entry->id)->lockForUpdate()->firstOrFail();

            if ($locked->status !== JournalEntry::STATUS_POSTED) {
                throw new RuntimeException("Journal {$locked->number} has already been reversed.");
            }

            if ($locked->reversal_of_id) {
                throw new RuntimeException("Journal {$locked->number} is itself a reversal and cannot be reversed again.");
            }

            $lines = $locked->lines()->get()->map(fn ($l) => [
                'account_id' => $l->account_id,
                'debit' => $l->credit,
                'credit' => $l->debit,
                'description' => $l->description,
            ])->all();

            $reversal = $this->post($lines, "Reversal of {$locked->number}: {$reason}", $date, $locked, 'reverse', $actor, $locked->id);

            $locked->update(['status' => JournalEntry::STATUS_REVERSED]);
            $this->audit->log('journal.reversed', "Reversed journal {$locked->number} · {$reason}", $locked, actor: $actor);

            return $reversal->fresh('lines.account');
        });
    }

    public function existing(Model $source, string $purpose = 'post'): ?JournalEntry
    {
        return JournalEntry::query()
            ->where('source_type', class_basename($source))
            ->where('source_id', $source->getKey())
            ->where('purpose', $purpose)
            ->first();
    }

    /**
     * Turns the caller's lines into whole cents against resolved accounts,
     * refusing anything that would leave the ledger out of balance.
     *
     * @return list<array{account_id: int, debit_cents: int, credit_cents: int, description: ?string}>
     */
    private function validate(array $lines): array
    {
        if (count($lines) < 2) {
            throw new RuntimeException('A journal entry needs at least two lines.');
        }

        $keys = array_values(array_unique(array_filter(array_column($lines, 'account'))));
        $bySystemKey = $keys
            ? Account::query()->whereIn('system_key', $keys)->pluck('id', 'system_key')->all()
            : [];

        // A company set up before a module shipped lacks that module's
        // accounts: add the missing standard ones once, then look again.
        if (count($bySystemKey) < count($keys) && ($company = app(TenantContext::class)->company())) {
            app(ChartOfAccounts::class)->seed($company);
            $bySystemKey = Account::query()->whereIn('system_key', $keys)->pluck('id', 'system_key')->all();
        }

        $resolved = [];

        foreach ($lines as $i => $line) {
            $accountId = $line['account_id'] ?? null;

            if (! $accountId && isset($line['account'])) {
                $accountId = $bySystemKey[$line['account']]
                    ?? throw new RuntimeException("The chart of accounts has no '{$line['account']}' account. Run the business setup to create the standard accounts.");
            }

            $debit = $this->cents($line['debit'] ?? 0);
            $credit = $this->cents($line['credit'] ?? 0);

            if ($debit < 0 || $credit < 0) {
                throw new RuntimeException('Line '.($i + 1).': amounts cannot be negative.');
            }

            if (($debit > 0) === ($credit > 0)) {
                throw new RuntimeException('Line '.($i + 1).': enter either a debit or a credit, not both and not neither.');
            }

            $resolved[] = [
                'account_id' => (int) $accountId,
                'debit_cents' => $debit,
                'credit_cents' => $credit,
                'description' => isset($line['description']) ? mb_substr((string) $line['description'], 0, 255) : null,
            ];
        }

        $ids = array_unique(array_column($resolved, 'account_id'));
        // Scoped to the tenant: another company's account id simply is not found.
        $active = Account::query()->whereIn('id', $ids)->where('is_active', true)->count();

        if ($active !== count($ids)) {
            throw new RuntimeException('Every line must use an active account from this company\'s chart of accounts.');
        }

        $debits = array_sum(array_column($resolved, 'debit_cents'));
        $credits = array_sum(array_column($resolved, 'credit_cents'));

        if ($debits !== $credits) {
            throw new RuntimeException(sprintf(
                'Debits (%s) and credits (%s) must be equal.',
                number_format($debits / 100, 2), number_format($credits / 100, 2),
            ));
        }

        return $resolved;
    }

    private function cents(float|int|string|null $amount): int
    {
        return (int) round(((float) $amount) * 100);
    }

    private function describe(Model $source): string
    {
        return $source->getAttribute('number') ?? class_basename($source).' #'.$source->getKey();
    }
}
