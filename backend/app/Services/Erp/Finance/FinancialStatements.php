<?php

namespace App\Services\Erp\Finance;

use App\Models\Erp\Account;
use App\Models\Erp\Finance\Budget;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * Profit and loss, balance sheet, cash flow and budget against actual, all
 * read straight from the journal so they cannot disagree with the trial
 * balance.
 *
 * Profit and loss leaves out the year-end closing entry (it would zero the
 * year it closes). The balance sheet keeps it, and shows the profit not yet
 * closed to retained earnings as its own equity line, so assets always equal
 * liabilities plus equity.
 *
 * The cash flow uses the direct method: every movement on a cash or bank
 * account (1100-1299) is attributed to the other accounts in the same entry
 * and grouped by what those accounts are. Transfers between cash accounts
 * cancel out and are not shown.
 */
class FinancialStatements
{
    public function __construct(private readonly Ledger $ledger) {}

    /** @return array<string, mixed> */
    public function profitAndLoss(string $from, string $to, bool $compare = true): array
    {
        [$priorFrom, $priorTo] = $this->priorPeriod($from, $to);
        $current = $this->ledger->totals($from, $to, false);
        $prior = $compare ? $this->ledger->totals($priorFrom, $priorTo, false) : [];

        $accounts = Account::query()->whereIn('type', ['income', 'expense'])->orderBy('code')->get();
        $amount = fn (Account $a, array $totals) => isset($totals[$a->id])
            ? round($a->type === 'income' ? $totals[$a->id]['credit'] - $totals[$a->id]['debit'] : $totals[$a->id]['debit'] - $totals[$a->id]['credit'], 2)
            : 0.0;

        $rows = $accounts->map(fn (Account $a) => [
            'account_id' => $a->id, 'code' => $a->code, 'name' => $a->name, 'type' => $a->type,
            'section' => $this->plSection($a),
            'amount' => $amount($a, $current),
            'prior' => $amount($a, $prior),
        ])->filter(fn ($r) => $r['amount'] != 0 || $r['prior'] != 0)->values();

        $sum = fn (string $section, string $key) => round($rows->where('section', $section)->sum($key), 2);
        $totals = [];
        foreach (['amount', 'prior'] as $key) {
            $income = $sum('income', $key);
            $costOfSales = $sum('cost_of_sales', $key);
            $operating = $sum('operating_expenses', $key);
            $totals[$key] = [
                'income' => $income,
                'cost_of_sales' => $costOfSales,
                'gross_profit' => round($income - $costOfSales, 2),
                'operating_expenses' => $operating,
                'expenses' => round($costOfSales + $operating, 2),
                'net_profit' => round($income - $costOfSales - $operating, 2),
            ];
        }

        return [
            'from' => $from, 'to' => $to,
            'prior_from' => $priorFrom, 'prior_to' => $priorTo,
            'rows' => $rows->all(),
            'totals' => $totals['amount'],
            'prior_totals' => $totals['prior'],
        ];
    }

    /** @return array<string, mixed> */
    public function balanceSheet(string $asOf): array
    {
        $totals = $this->ledger->totals(null, $asOf);
        $accounts = Account::query()->orderBy('code')->get();
        $net = fn (Account $a) => isset($totals[$a->id])
            ? round($a->isDebitNormal() ? $totals[$a->id]['debit'] - $totals[$a->id]['credit'] : $totals[$a->id]['credit'] - $totals[$a->id]['debit'], 2)
            : 0.0;

        $rows = $accounts->whereIn('type', ['asset', 'liability', 'equity'])->map(fn (Account $a) => [
            'account_id' => $a->id, 'code' => $a->code, 'name' => $a->name, 'type' => $a->type,
            'section' => $this->bsSection($a),
            'amount' => $net($a),
        ])->filter(fn ($r) => $r['amount'] != 0)->values();

        // Income less expenses over all time, including closing entries:
        // what has not yet been closed to retained earnings.
        $earnings = round($accounts->whereIn('type', ['income', 'expense'])
            ->sum(fn (Account $a) => $a->type === 'income' ? $net($a) : -$net($a)), 2);

        $assets = round($rows->where('type', 'asset')->sum('amount'), 2);
        $liabilities = round($rows->where('type', 'liability')->sum('amount'), 2);
        $equity = round($rows->where('type', 'equity')->sum('amount') + $earnings, 2);

        return [
            'as_of' => $asOf,
            'rows' => $rows->all(),
            'current_earnings' => $earnings,
            'totals' => [
                'current_assets' => round($rows->where('section', 'current_assets')->sum('amount'), 2),
                'non_current_assets' => round($rows->where('section', 'non_current_assets')->sum('amount'), 2),
                'assets' => $assets,
                'current_liabilities' => round($rows->where('section', 'current_liabilities')->sum('amount'), 2),
                'non_current_liabilities' => round($rows->where('section', 'non_current_liabilities')->sum('amount'), 2),
                'liabilities' => $liabilities,
                'equity' => $equity,
                'liabilities_and_equity' => round($liabilities + $equity, 2),
            ],
            'balanced' => abs($assets - $liabilities - $equity) < 0.005,
        ];
    }

    /** @return array<string, mixed> */
    public function cashFlow(string $from, string $to): array
    {
        $cash = $this->ledger->cashAccountIds();
        $dayBefore = CarbonImmutable::parse($from)->subDay()->toDateString();
        $opening = round(array_sum($this->ledger->balances($cash, $dayBefore)), 2);
        $closing = round(array_sum($this->ledger->balances($cash, $to)), 2);

        $entryIds = $cash ? $this->ledger->lines($from, $to)->whereIn('journal_lines.account_id', $cash)
            ->distinct()->pluck('journal_entries.id')->all() : [];

        // Each non-cash line's credit less debit is the cash it brought in.
        $flows = [];
        if ($entryIds) {
            $this->ledger->lines()->whereIn('journal_entries.id', $entryIds)
                ->whereNotIn('journal_lines.account_id', $cash)
                ->groupBy('journal_lines.account_id')
                ->selectRaw('journal_lines.account_id, SUM(journal_lines.credit) - SUM(journal_lines.debit) AS flow')
                ->get()
                ->each(function ($r) use (&$flows) {
                    $flows[(int) $r->account_id] = round((float) $r->flow, 2);
                });
        }

        $accounts = Account::query()->whereIn('id', array_keys($flows))->orderBy('code')->get();
        $rows = $accounts->map(fn (Account $a) => [
            'account_id' => $a->id, 'code' => $a->code, 'name' => $a->name, 'type' => $a->type,
            'activity' => $this->activity($a),
            'amount' => $flows[$a->id],
        ])->filter(fn ($r) => $r['amount'] != 0)->values();

        $activity = fn (string $key) => round($rows->where('activity', $key)->sum('amount'), 2);
        $net = round($rows->sum('amount'), 2);

        return [
            'method' => 'direct',
            'from' => $from, 'to' => $to,
            'rows' => $rows->all(),
            'totals' => [
                'operating' => $activity('operating'),
                'investing' => $activity('investing'),
                'financing' => $activity('financing'),
                'net_change' => $net,
                'opening_cash' => $opening,
                'closing_cash' => $closing,
            ],
            'reconciles' => abs($opening + $net - $closing) < 0.005,
        ];
    }

    /** @return array<string, mixed> */
    public function budgetVsActual(int $year, ?int $throughMonth = null): array
    {
        $months = FiscalYear::months($year);
        $through = max(1, min(12, $throughMonth ?? 12));
        $from = FiscalYear::start($year)->toDateString();
        $to = CarbonImmutable::createFromFormat('Y-m', $months[$through - 1])->endOfMonth()->toDateString();

        $budget = Budget::query()->with('lines')->where('fiscal_year', $year)->first();
        $budgeted = collect($budget?->lines ?? [])->where('month', '<=', $through)->groupBy('account_id')
            ->map(fn (Collection $lines) => round($lines->sum(fn ($l) => (float) $l->amount), 2));
        $actual = $this->ledger->totals($from, $to, false);

        $accounts = Account::query()->whereIn('type', ['income', 'expense'])->orderBy('code')->get();
        $rows = $accounts->map(function (Account $a) use ($budgeted, $actual) {
            $b = (float) ($budgeted[$a->id] ?? 0);
            $t = $actual[$a->id] ?? ['debit' => 0, 'credit' => 0];
            $act = round($a->type === 'income' ? $t['credit'] - $t['debit'] : $t['debit'] - $t['credit'], 2);
            // Positive variance is favourable: more income, or less spending, than planned.
            $variance = round($a->type === 'income' ? $act - $b : $b - $act, 2);

            return [
                'account_id' => $a->id, 'code' => $a->code, 'name' => $a->name, 'type' => $a->type,
                'budget' => $b, 'actual' => $act, 'variance' => $variance,
                'used_percent' => $b != 0.0 ? round($act / $b * 100, 1) : null,
            ];
        })->filter(fn ($r) => $r['budget'] != 0 || $r['actual'] != 0)->values();

        $sum = fn (string $type, string $key) => round($rows->where('type', $type)->sum($key), 2);

        return [
            'fiscal_year' => $year, 'through_month' => $through, 'from' => $from, 'to' => $to,
            'has_budget' => (bool) $budget,
            'rows' => $rows->all(),
            'totals' => [
                'income_budget' => $sum('income', 'budget'), 'income_actual' => $sum('income', 'actual'),
                'expense_budget' => $sum('expense', 'budget'), 'expense_actual' => $sum('expense', 'actual'),
                'net_budget' => round($sum('income', 'budget') - $sum('expense', 'budget'), 2),
                'net_actual' => round($sum('income', 'actual') - $sum('expense', 'actual'), 2),
            ],
        ];
    }

    /**
     * The period of the same length just before: whole months compare with
     * the same number of months before, any other range with the same
     * number of days before.
     *
     * @return array{0: string, 1: string}
     */
    public function priorPeriod(string $from, string $to): array
    {
        $start = CarbonImmutable::parse($from);
        $end = CarbonImmutable::parse($to);

        if ($start->day === 1 && $end->isLastOfMonth()) {
            $months = ($end->year - $start->year) * 12 + $end->month - $start->month + 1;

            return [$start->subMonthsNoOverflow($months)->toDateString(), $start->subDay()->toDateString()];
        }

        $days = (int) $start->diffInDays($end) + 1;

        return [$start->subDays($days)->toDateString(), $start->subDay()->toDateString()];
    }

    private function plSection(Account $account): string
    {
        if ($account->type === 'income') {
            return 'income';
        }

        return str_starts_with((string) $account->code, '5') ? 'cost_of_sales' : 'operating_expenses';
    }

    private function bsSection(Account $account): string
    {
        $code = ctype_digit((string) $account->code) ? (int) $account->code : 0;

        return match ($account->type) {
            'asset' => $code >= 1500 && $code < 2000 ? 'non_current_assets' : 'current_assets',
            'liability' => $code >= 2500 && $code < 3000 ? 'non_current_liabilities' : 'current_liabilities',
            default => 'equity',
        };
    }

    /**
     * Which activity a counter-account's cash belongs to: fixed assets are
     * investing, equity and long-term liabilities (2500-2999) financing,
     * everything else (income, expenses, receivables, payables, stock, tax)
     * operating.
     */
    private function activity(Account $account): string
    {
        $code = ctype_digit((string) $account->code) ? (int) $account->code : 0;

        return match (true) {
            $account->type === 'asset' && $code >= 1500 && $code < 2000 => 'investing',
            $account->type === 'equity', $account->type === 'liability' && $code >= 2500 && $code < 3000 => 'financing',
            default => 'operating',
        };
    }
}
