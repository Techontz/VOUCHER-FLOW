<?php

namespace App\Http\Controllers\Api\Erp\Finance;

use App\Http\Controllers\Controller;
use App\Services\Erp\Finance\FinancialStatements;
use App\Services\Erp\Finance\FiscalYear;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\StreamedResponse;

/** The statements, as JSON for the screens or CSV (?format=csv) for a spreadsheet. */
class StatementController extends Controller
{
    private const SECTION = [
        'income' => 'Income', 'cost_of_sales' => 'Cost of sales', 'operating_expenses' => 'Operating expenses',
        'current_assets' => 'Current assets', 'non_current_assets' => 'Non-current assets',
        'current_liabilities' => 'Current liabilities', 'non_current_liabilities' => 'Non-current liabilities', 'equity' => 'Equity',
        'operating' => 'Operating activities', 'investing' => 'Investing activities', 'financing' => 'Financing activities',
    ];

    public function __construct(private readonly FinancialStatements $statements) {}

    public function profitAndLoss(Request $request): JsonResponse|StreamedResponse
    {
        [$from, $to] = $this->range($request);
        $data = $this->statements->profitAndLoss($from, $to, $request->boolean('compare', true));

        if ($request->query('format') === 'csv') {
            $rows = [['Section', 'Code', 'Account', "{$from} to {$to}", "{$data['prior_from']} to {$data['prior_to']}"]];
            foreach ($data['rows'] as $r) {
                $rows[] = [self::SECTION[$r['section']], $r['code'], $r['name'], $r['amount'], $r['prior']];
            }
            foreach (['income' => 'Total income', 'cost_of_sales' => 'Total cost of sales', 'gross_profit' => 'Gross profit', 'operating_expenses' => 'Total operating expenses', 'net_profit' => 'Net profit'] as $key => $label) {
                $rows[] = ['', '', $label, $data['totals'][$key], $data['prior_totals'][$key]];
            }

            return $this->csv("profit-and-loss-{$from}-to-{$to}.csv", $rows);
        }

        return response()->json(['data' => $data]);
    }

    public function balanceSheet(Request $request): JsonResponse|StreamedResponse
    {
        $asOf = $request->validate(['as_of' => ['nullable', 'date']])['as_of'] ?? now()->toDateString();
        $data = $this->statements->balanceSheet($asOf);

        if ($request->query('format') === 'csv') {
            $rows = [['Section', 'Code', 'Account', "As at {$asOf}"]];
            foreach ($data['rows'] as $r) {
                $rows[] = [self::SECTION[$r['section']], $r['code'], $r['name'], $r['amount']];
            }
            $rows[] = ['Equity', '', 'Profit not yet closed to retained earnings', $data['current_earnings']];
            $rows[] = ['', '', 'Total assets', $data['totals']['assets']];
            $rows[] = ['', '', 'Total liabilities', $data['totals']['liabilities']];
            $rows[] = ['', '', 'Total equity', $data['totals']['equity']];
            $rows[] = ['', '', 'Total liabilities and equity', $data['totals']['liabilities_and_equity']];

            return $this->csv("balance-sheet-{$asOf}.csv", $rows);
        }

        return response()->json(['data' => $data]);
    }

    public function cashFlow(Request $request): JsonResponse|StreamedResponse
    {
        [$from, $to] = $this->range($request);
        $data = $this->statements->cashFlow($from, $to);

        if ($request->query('format') === 'csv') {
            $rows = [['Activity', 'Code', 'Account', 'Cash in (out)'], ['', '', 'Opening cash and bank', $data['totals']['opening_cash']]];
            foreach ($data['rows'] as $r) {
                $rows[] = [self::SECTION[$r['activity']], $r['code'], $r['name'], $r['amount']];
            }
            foreach (['operating' => 'Net cash from operating activities', 'investing' => 'Net cash from investing activities', 'financing' => 'Net cash from financing activities', 'net_change' => 'Net change in cash', 'closing_cash' => 'Closing cash and bank'] as $key => $label) {
                $rows[] = ['', '', $label, $data['totals'][$key]];
            }

            return $this->csv("cash-flow-{$from}-to-{$to}.csv", $rows);
        }

        return response()->json(['data' => $data]);
    }

    public function budgetVsActual(Request $request): JsonResponse|StreamedResponse
    {
        $q = $request->validate(['year' => ['nullable', 'integer', 'between:2000,2100'], 'through_month' => ['nullable', 'integer', 'between:1,12']]);
        $year = (int) ($q['year'] ?? FiscalYear::of(now()->toImmutable()));
        $data = $this->statements->budgetVsActual($year, $q['through_month'] ?? null);

        if ($request->query('format') === 'csv') {
            $rows = [['Type', 'Code', 'Account', 'Budget', 'Actual', 'Variance (favourable +)', 'Used %']];
            foreach ($data['rows'] as $r) {
                $rows[] = [ucfirst($r['type']), $r['code'], $r['name'], $r['budget'], $r['actual'], $r['variance'], $r['used_percent']];
            }

            return $this->csv("budget-vs-actual-{$year}.csv", $rows);
        }

        return response()->json(['data' => $data]);
    }

    /** @return array{0: string, 1: string} */
    private function range(Request $request): array
    {
        $q = $request->validate(['from' => ['nullable', 'date'], 'to' => ['nullable', 'date', 'after_or_equal:from']]);

        return [$q['from'] ?? now()->startOfMonth()->toDateString(), $q['to'] ?? now()->toDateString()];
    }

    /** @param  list<list<mixed>>  $rows */
    private function csv(string $filename, array $rows): StreamedResponse
    {
        return response()->streamDownload(function () use ($rows) {
            $out = fopen('php://output', 'w');
            foreach ($rows as $row) {
                fputcsv($out, $row, ',', '"', '');
            }
            fclose($out);
        }, $filename, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }
}
