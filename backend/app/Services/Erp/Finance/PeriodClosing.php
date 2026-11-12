<?php

namespace App\Services\Erp\Finance;

use App\Models\Erp\Account;
use App\Models\Erp\Finance\BankTransfer;
use App\Models\Erp\Finance\CashbookEntry;
use App\Models\Erp\Finance\ClosedPeriod;
use App\Models\Erp\Finance\YearEndClosing;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\JournalPoster;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Closing months and years.
 *
 * A closed month refuses every posting dated inside it (PeriodLock). Closing
 * the year posts one entry that empties every income and expense account
 * into retained earnings, dated the year's last day, and closes all twelve
 * months; it can happen once per year.
 */
class PeriodClosing
{
    public function __construct(
        private readonly JournalPoster $journal,
        private readonly AuditLogger $audit,
        private readonly Ledger $ledger,
    ) {}

    /** @return array<string, mixed> */
    public function year(int $year): array
    {
        $rows = ClosedPeriod::query()->with(['closer:id,name', 'reopener:id,name'])
            ->whereIn('period', FiscalYear::months($year))->get()->keyBy('period');
        $counts = $this->ledger->lines(FiscalYear::start($year)->toDateString(), FiscalYear::end($year)->toDateString())
            ->selectRaw("DATE_FORMAT(journal_entries.entry_date, '%Y-%m') AS period, COUNT(DISTINCT journal_entries.id) AS entries")
            ->groupBy('period')->pluck('entries', 'period');
        $today = now()->toDateString();

        $months = array_map(function (string $period) use ($rows, $counts, $today) {
            $start = CarbonImmutable::createFromFormat('Y-m', $period)->startOfMonth();
            $row = $rows[$period] ?? null;

            return [
                'period' => $period,
                'starts_on' => $start->toDateString(),
                'ends_on' => $start->endOfMonth()->toDateString(),
                'status' => $row?->status === ClosedPeriod::STATUS_CLOSED ? 'closed' : 'open',
                'ended' => $start->endOfMonth()->toDateString() < $today,
                'entries' => (int) ($counts[$period] ?? 0),
                'closed_at' => $row?->closed_at, 'closed_by' => $row?->closer?->name,
                'reopened_at' => $row?->reopened_at, 'reopened_by' => $row?->reopener?->name, 'reopen_reason' => $row?->reopen_reason,
            ];
        }, FiscalYear::months($year));

        $closing = YearEndClosing::query()->with('closer:id,name', 'journal:id,number')->where('fiscal_year', $year)->first();

        return [
            'fiscal_year' => $year,
            'starts_on' => FiscalYear::start($year)->toDateString(),
            'ends_on' => FiscalYear::end($year)->toDateString(),
            'months' => $months,
            'year_end' => $closing,
            'can_close_year' => ! $closing && FiscalYear::end($year)->toDateString() < $today,
        ];
    }

    public function close(string $period, User $actor): ClosedPeriod
    {
        $start = $this->parse($period);
        $end = $start->endOfMonth();

        if ($end->toDateString() >= now()->toDateString()) {
            throw new RuntimeException("{$start->format('F Y')} has not ended yet; a month can be closed once it is over.");
        }

        $drafts = CashbookEntry::query()->where('status', CashbookEntry::STATUS_DRAFT)->whereBetween('entry_date', [$start->toDateString(), $end->toDateString()])->count()
            + BankTransfer::query()->where('status', BankTransfer::STATUS_DRAFT)->whereBetween('transfer_date', [$start->toDateString(), $end->toDateString()])->count();

        if ($drafts > 0) {
            throw new RuntimeException("{$drafts} draft receipt(s), payment(s) or transfer(s) are dated in {$start->format('F Y')}. Post or cancel them before closing the month.");
        }

        return DB::transaction(function () use ($period, $start, $end, $actor) {
            $row = ClosedPeriod::query()->where('period', $period)->lockForUpdate()->first();

            if ($row?->status === ClosedPeriod::STATUS_CLOSED) {
                throw new RuntimeException("{$start->format('F Y')} is already closed.");
            }

            $row ??= new ClosedPeriod(['period' => $period]);
            $row->fill([
                'starts_on' => $start->toDateString(), 'ends_on' => $end->toDateString(),
                'status' => ClosedPeriod::STATUS_CLOSED, 'closed_by' => $actor->id, 'closed_at' => now(),
            ])->save();

            $this->audit->log('finance.period.closed', "Closed {$start->format('F Y')}", $row, actor: $actor);

            return $row;
        });
    }

    public function reopen(string $period, string $reason, User $actor): ClosedPeriod
    {
        $start = $this->parse($period);

        if (YearEndClosing::query()->where('fiscal_year', FiscalYear::of($start))->exists()) {
            throw new RuntimeException("The fiscal year containing {$start->format('F Y')} has been closed to retained earnings; its months cannot be reopened.");
        }

        return DB::transaction(function () use ($period, $start, $reason, $actor) {
            $row = ClosedPeriod::query()->where('period', $period)->lockForUpdate()->first();

            if (! $row || $row->status !== ClosedPeriod::STATUS_CLOSED) {
                throw new RuntimeException("{$start->format('F Y')} is not closed.");
            }

            $row->update([
                'status' => ClosedPeriod::STATUS_OPEN, 'reopened_by' => $actor->id, 'reopened_at' => now(),
                'reopen_reason' => mb_substr($reason, 0, 255),
            ]);
            $this->audit->log('finance.period.reopened', "Reopened {$start->format('F Y')} · {$reason}", $row, actor: $actor);

            return $row;
        });
    }

    public function closeYear(int $year, User $actor): YearEndClosing
    {
        $start = FiscalYear::start($year);
        $end = FiscalYear::end($year);

        if ($end->toDateString() >= now()->toDateString()) {
            throw new RuntimeException("Fiscal year {$year} ends on {$end->format('j M Y')}; it can be closed once it is over.");
        }

        return DB::transaction(function () use ($year, $start, $end, $actor) {
            // Serialises two people closing the same year at once.
            DB::table('companies')->where('id', $actor->company_id)->lockForUpdate()->first();

            if (YearEndClosing::query()->where('fiscal_year', $year)->exists()) {
                throw new RuntimeException("Fiscal year {$year} has already been closed.");
            }

            $totals = $this->ledger->totals($start->toDateString(), $end->toDateString(), false);
            $accounts = Account::query()->whereIn('type', ['income', 'expense'])->whereIn('id', array_keys($totals))->orderBy('code')->get();
            $lines = [];
            $profitCents = 0;

            foreach ($accounts as $account) {
                // Natural-side balance in cents; the closing line takes it to nil.
                $cents = (int) round(($totals[$account->id]['debit'] - $totals[$account->id]['credit']) * 100);
                if ($cents === 0) {
                    continue;
                }
                $profitCents -= $cents;
                $lines[] = $cents > 0
                    ? ['account_id' => $account->id, 'credit' => $cents / 100, 'description' => "Close {$year}"]
                    : ['account_id' => $account->id, 'debit' => -$cents / 100, 'description' => "Close {$year}"];
            }

            if (! $lines) {
                throw new RuntimeException("Fiscal year {$year} has no income or expenses to close.");
            }

            $lines[] = $profitCents >= 0
                ? ['account' => 'retained_earnings', 'credit' => $profitCents / 100, 'description' => "Profit for {$year}"]
                : ['account' => 'retained_earnings', 'debit' => -$profitCents / 100, 'description' => "Loss for {$year}"];
            $lines = array_values(array_filter($lines, fn ($l) => ($l['debit'] ?? 0) > 0 || ($l['credit'] ?? 0) > 0));

            $closing = YearEndClosing::create([
                'fiscal_year' => $year, 'starts_on' => $start->toDateString(), 'ends_on' => $end->toDateString(),
                'net_profit' => $profitCents / 100, 'closed_by' => $actor->id,
            ]);

            $entry = PeriodLock::bypass(fn () => $this->journal->post($lines, "Year-end closing {$year}: profit to retained earnings", $end->toDateString(), $closing, 'post', $actor));
            $closing->update(['journal_entry_id' => $entry->id]);

            foreach (FiscalYear::months($year) as $period) {
                $month = CarbonImmutable::createFromFormat('Y-m', $period)->startOfMonth();
                $row = ClosedPeriod::query()->firstOrNew(['period' => $period]);
                if ($row->status !== ClosedPeriod::STATUS_CLOSED) {
                    $row->fill([
                        'starts_on' => $month->toDateString(), 'ends_on' => $month->endOfMonth()->toDateString(),
                        'status' => ClosedPeriod::STATUS_CLOSED, 'closed_by' => $actor->id, 'closed_at' => now(),
                    ])->save();
                }
            }

            $this->audit->log('finance.year.closed', "Closed fiscal year {$year}: ".number_format($profitCents / 100, 2).' to retained earnings', $closing, actor: $actor);

            return $closing->fresh('journal.lines.account');
        });
    }

    private function parse(string $period): CarbonImmutable
    {
        if (! preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $period)) {
            throw new RuntimeException('A period is a month written YYYY-MM.');
        }

        return CarbonImmutable::createFromFormat('Y-m', $period)->startOfMonth();
    }
}
