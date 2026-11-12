<?php

namespace App\Services\Erp;

use App\Models\Company;
use App\Models\Erp\Account;
use App\Support\Erp\ModuleRegistry;

/**
 * The standard chart a company starts with, and the trial balance.
 *
 * Accounts the posting rules depend on carry a system_key. A company may
 * rename or renumber them; the rules keep finding them by key.
 */
class ChartOfAccounts
{
    /** @var list<array{0: string, 1: string, 2: string, 3: ?string}> code, name, type, system key */
    public const STANDARD = [
        ['1100', 'Cash on hand', 'asset', 'cash'],
        ['1110', 'Petty cash', 'asset', 'petty_cash'],
        ['1200', 'Bank', 'asset', 'bank'],
        ['1300', 'Accounts receivable', 'asset', 'receivable'],
        ['1350', 'VAT receivable (input)', 'asset', 'vat_input'],
        ['1400', 'Inventory', 'asset', 'inventory'],
        ['1500', 'Fixed assets', 'asset', 'fixed_assets'],
        ['1510', 'Accumulated depreciation', 'asset', 'accumulated_depreciation'],
        ['2100', 'Accounts payable', 'liability', 'payable'],
        ['2150', 'Goods received not invoiced', 'liability', 'grni'],
        ['2200', 'VAT payable (output)', 'liability', 'vat_output'],
        ['2300', 'Payroll liabilities', 'liability', 'payroll_liabilities'],
        ['2400', 'Accrued expenses', 'liability', 'accruals'],
        ['3000', 'Share capital', 'equity', 'share_capital'],
        ['3100', 'Retained earnings', 'equity', 'retained_earnings'],
        ['3900', 'Opening balance equity', 'equity', 'opening_equity'],
        ['4000', 'Sales revenue', 'income', 'sales'],
        ['4100', 'Transport revenue', 'income', 'transport_revenue'],
        ['4900', 'Other income', 'income', 'other_income'],
        ['5000', 'Cost of goods sold', 'expense', 'cogs'],
        ['5200', 'Stock issued to operations', 'expense', 'stock_issues'],
        ['5300', 'Inventory adjustments', 'expense', 'stock_adjustments'],
        ['6000', 'Salaries & wages', 'expense', 'salaries'],
        ['6100', 'Fuel', 'expense', 'fuel'],
        ['6200', 'Vehicle repairs & maintenance', 'expense', 'vehicle_maintenance'],
        ['6300', 'Rent', 'expense', 'rent'],
        ['6400', 'Utilities', 'expense', 'utilities'],
        ['6500', 'Office & administration', 'expense', 'admin'],
        ['6900', 'Other expenses', 'expense', 'other_expenses'],
    ];

    /** Idempotent: an account that already exists (by system key or code) is left as the company has it. */
    /**
     * The core chart plus the accounts each module brings.
     *
     * @return list<array{0: string, 1: string, 2: string, 3: string}>
     */
    public static function standard(): array
    {
        return [...self::STANDARD, ...ModuleRegistry::accounts()];
    }

    public function seed(Company $company): int
    {
        $created = 0;

        foreach (self::standard() as [$code, $name, $type, $key]) {
            $exists = Account::query()
                ->where(fn ($q) => $q->where('system_key', $key)->orWhere('code', $code))
                ->exists();

            if (! $exists) {
                Account::create([
                    'company_id' => $company->id,
                    'code' => $code, 'name' => $name, 'type' => $type, 'system_key' => $key,
                ]);
                $created++;
            }
        }

        return $created;
    }

    /**
     * Debit and credit totals per account, with the net in the account's
     * natural direction. Reversed entries stay in: their reversals cancel them.
     *
     * @return array{rows: list<array<string, mixed>>, total_debit: float, total_credit: float, balanced: bool}
     */
    public function trialBalance(?string $from = null, ?string $to = null): array
    {
        $rows = Account::query()
            ->leftJoin('journal_lines', 'journal_lines.account_id', '=', 'accounts.id')
            ->leftJoin('journal_entries', function ($join) use ($from, $to) {
                $join->on('journal_entries.id', '=', 'journal_lines.journal_entry_id');
                if ($from) {
                    $join->where('journal_entries.entry_date', '>=', $from);
                }
                if ($to) {
                    $join->where('journal_entries.entry_date', '<=', $to);
                }
            })
            ->groupBy('accounts.id', 'accounts.code', 'accounts.name', 'accounts.type')
            ->orderBy('accounts.code')
            ->selectRaw('accounts.id, accounts.code, accounts.name, accounts.type,
                COALESCE(SUM(CASE WHEN journal_entries.id IS NOT NULL THEN journal_lines.debit END), 0) AS debit,
                COALESCE(SUM(CASE WHEN journal_entries.id IS NOT NULL THEN journal_lines.credit END), 0) AS credit')
            ->get()
            ->map(function ($r) {
                $debit = round((float) $r->debit, 2);
                $credit = round((float) $r->credit, 2);
                $debitNormal = in_array($r->type, Account::DEBIT_NORMAL, true);

                return [
                    'account_id' => $r->id,
                    'code' => $r->code,
                    'name' => $r->name,
                    'type' => $r->type,
                    'debit' => $debit,
                    'credit' => $credit,
                    'balance' => round($debitNormal ? $debit - $credit : $credit - $debit, 2),
                ];
            })
            ->filter(fn ($r) => $r['debit'] != 0 || $r['credit'] != 0)
            ->values()
            ->all();

        $totalDebit = round(array_sum(array_column($rows, 'debit')), 2);
        $totalCredit = round(array_sum(array_column($rows, 'credit')), 2);

        return [
            'rows' => $rows,
            'total_debit' => $totalDebit,
            'total_credit' => $totalCredit,
            'balanced' => abs($totalDebit - $totalCredit) < 0.005,
        ];
    }
}
