<?php

namespace App\Http\Controllers\Api\Erp\Finance;

use App\Http\Controllers\Controller;
use App\Models\Erp\Account;
use App\Models\Erp\Finance\AssetClass;
use App\Models\Erp\Finance\AssetDepreciationRun;
use App\Models\Erp\Finance\BankAccount;
use App\Models\Erp\Finance\BankReconciliation;
use App\Models\Erp\Finance\BankTransfer;
use App\Models\Erp\Finance\CashbookEntry;
use App\Models\Erp\Finance\ClosedPeriod;
use App\Models\Erp\Finance\FixedAsset;
use App\Services\Erp\Finance\AssetClasses;
use App\Services\Erp\Finance\Depreciation;
use App\Services\Erp\Finance\FinancialStatements;
use App\Services\Erp\Finance\Ledger;
use Illuminate\Http\JsonResponse;

/** The two landing screens: finance (cash, receivables, payables, this month) and assets. */
class OverviewController extends Controller
{
    public function finance(Ledger $ledger, FinancialStatements $statements): JsonResponse
    {
        $cashIds = $ledger->cashAccountIds();
        $balances = $ledger->balances($cashIds);
        $banks = BankAccount::query()->get()->keyBy('account_id');

        $cash = Account::query()->whereIn('id', $cashIds)->orderBy('code')->get()
            ->map(fn (Account $a) => [
                'account_id' => $a->id, 'code' => $a->code, 'name' => $a->name,
                'bank_account_id' => $banks[$a->id]->id ?? null,
                'type' => $banks[$a->id]->type ?? ($a->system_key === 'bank' ? 'bank' : 'cash'),
                'is_active' => $banks[$a->id]->is_active ?? $a->is_active,
                'balance' => $balances[$a->id] ?? 0.0,
            ])
            ->filter(fn ($r) => $r['bank_account_id'] || $r['balance'] != 0)
            ->values();

        $control = fn (string $key) => ($id = Account::query()->where('system_key', $key)->value('id')) ? $ledger->balance($id) : 0.0;
        $monthStart = now()->startOfMonth()->toDateString();
        $pl = $statements->profitAndLoss($monthStart, now()->endOfMonth()->toDateString());
        $current = now()->format('Y-m');
        $lastClosed = ClosedPeriod::query()->where('status', ClosedPeriod::STATUS_CLOSED)->max('period');

        return response()->json(['data' => [
            'cash' => $cash,
            'cash_total' => round($cash->sum('balance'), 2),
            'receivables' => $control('receivable'),
            // Liabilities read credit-positive.
            'payables' => -$control('payable'),
            'month' => ['from' => $pl['from'], 'to' => $pl['to'], 'totals' => $pl['totals'], 'prior_totals' => $pl['prior_totals']],
            'periods' => [
                'current' => $current,
                'current_closed' => ClosedPeriod::query()->where('period', $current)->where('status', ClosedPeriod::STATUS_CLOSED)->exists(),
                'last_closed' => $lastClosed,
            ],
            'drafts' => [
                'cashbook' => CashbookEntry::query()->where('status', CashbookEntry::STATUS_DRAFT)->count(),
                'transfers' => BankTransfer::query()->where('status', BankTransfer::STATUS_DRAFT)->count(),
            ],
            'open_reconciliations' => BankReconciliation::query()->where('status', BankReconciliation::STATUS_OPEN)->with('bankAccount:id,name')->get(['id', 'number', 'bank_account_id', 'statement_date']),
            'recent' => CashbookEntry::query()->with('bankAccount:id,name', 'account:id,code,name')->latest('entry_date')->latest('id')->limit(6)->get(),
        ]]);
    }

    public function assets(AssetClasses $classes, Depreciation $depreciation): JsonResponse
    {
        $classes->ensureDefaults();
        $assets = FixedAsset::query()->with('assetClass:id,name')->get();
        $live = $assets->where('status', FixedAsset::STATUS_ACTIVE);
        $latest = AssetDepreciationRun::query()->latest('period')->first();
        $next = $latest ? now()->createFromFormat('Y-m', $latest->period)->startOfMonth()->addMonth()->format('Y-m') : now()->subMonth()->format('Y-m');

        return response()->json(['data' => [
            'counts' => [
                'draft' => $assets->where('status', FixedAsset::STATUS_DRAFT)->count(),
                'active' => $live->count(),
                'disposed' => $assets->where('status', FixedAsset::STATUS_DISPOSED)->count(),
            ],
            'cost' => round($live->sum(fn ($a) => (float) $a->cost), 2),
            'accumulated' => round($live->sum(fn ($a) => (float) $a->accumulated_depreciation), 2),
            'book_value' => round($live->sum(fn ($a) => $a->bookValue()), 2),
            'by_class' => AssetClass::query()->orderBy('code')->get()->map(fn (AssetClass $c) => [
                'id' => $c->id, 'code' => $c->code, 'name' => $c->name,
                'count' => $live->where('asset_class_id', $c->id)->count(),
                'cost' => round($live->where('asset_class_id', $c->id)->sum(fn ($a) => (float) $a->cost), 2),
                'book_value' => round($live->where('asset_class_id', $c->id)->sum(fn ($a) => $a->bookValue()), 2),
            ])->values(),
            'latest_run' => $latest,
            'next_period' => $next <= now()->format('Y-m') ? $next : null,
            'next_due' => $next <= now()->format('Y-m') ? $depreciation->preview($next)['total'] : 0,
            'disposed_this_year' => $assets->where('status', FixedAsset::STATUS_DISPOSED)
                ->filter(fn ($a) => $a->disposal_date?->year === now()->year)->values()
                ->map(fn ($a) => $a->only(['id', 'tag', 'name', 'disposal_date', 'disposal_proceeds', 'disposal_gain_loss'])),
        ]]);
    }
}
