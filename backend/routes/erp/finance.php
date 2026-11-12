<?php

use App\Http\Controllers\Api\Erp\Finance\AssetClassController;
use App\Http\Controllers\Api\Erp\Finance\BankAccountController;
use App\Http\Controllers\Api\Erp\Finance\BankTransferController;
use App\Http\Controllers\Api\Erp\Finance\BudgetController;
use App\Http\Controllers\Api\Erp\Finance\CashbookController;
use App\Http\Controllers\Api\Erp\Finance\DepreciationController;
use App\Http\Controllers\Api\Erp\Finance\FixedAssetController;
use App\Http\Controllers\Api\Erp\Finance\OverviewController;
use App\Http\Controllers\Api\Erp\Finance\PeriodController;
use App\Http\Controllers\Api\Erp\Finance\ReconciliationController;
use App\Http\Controllers\Api\Erp\Finance\StatementController;
use Illuminate\Support\Facades\Route;

/*
| Finance (extends the core 'accounting' module) and fixed assets ('assets').
| Required inside the authenticated, tenant-scoped /api/erp group.
*/

Route::middleware('module:accounting')->prefix('finance')->group(function () {
    Route::middleware('permission:finance.view')->group(function () {
        Route::get('overview', [OverviewController::class, 'finance']);
        Route::get('bank-accounts', [BankAccountController::class, 'index']);
        Route::get('bank-accounts/{bankAccount}', [BankAccountController::class, 'show']);
        Route::get('transfers', [BankTransferController::class, 'index']);
        Route::get('transfers/{bankTransfer}', [BankTransferController::class, 'show']);
        Route::get('cashbook', [CashbookController::class, 'index']);
        Route::get('cashbook/accounts', [CashbookController::class, 'accounts']);
        Route::get('cashbook/{cashbookEntry}', [CashbookController::class, 'show']);
        Route::get('reconciliations', [ReconciliationController::class, 'index']);
        Route::get('reconciliations/{bankReconciliation}', [ReconciliationController::class, 'show']);
        Route::get('periods', [PeriodController::class, 'index']);
        Route::get('budgets/{year}', [BudgetController::class, 'show'])->whereNumber('year');
    });

    Route::middleware('permission:finance.bank')->group(function () {
        Route::post('bank-accounts', [BankAccountController::class, 'store']);
        Route::put('bank-accounts/{bankAccount}', [BankAccountController::class, 'update']);

        Route::post('transfers', [BankTransferController::class, 'store']);
        Route::put('transfers/{bankTransfer}', [BankTransferController::class, 'update']);
        Route::post('transfers/{bankTransfer}/post', [BankTransferController::class, 'post']);
        Route::post('transfers/{bankTransfer}/reverse', [BankTransferController::class, 'reverse']);
        Route::post('transfers/{bankTransfer}/cancel', [BankTransferController::class, 'cancel']);

        Route::post('reconciliations', [ReconciliationController::class, 'store']);
        Route::put('reconciliations/{bankReconciliation}', [ReconciliationController::class, 'update']);
        Route::delete('reconciliations/{bankReconciliation}', [ReconciliationController::class, 'destroy']);
        Route::post('reconciliations/{bankReconciliation}/lines', [ReconciliationController::class, 'addLines']);
        Route::post('reconciliations/{bankReconciliation}/import', [ReconciliationController::class, 'import']);
        Route::post('reconciliations/{bankReconciliation}/auto-match', [ReconciliationController::class, 'autoMatch']);
        Route::post('reconciliations/{bankReconciliation}/complete', [ReconciliationController::class, 'complete']);
        Route::delete('reconciliations/{bankReconciliation}/lines/{line}', [ReconciliationController::class, 'deleteLine'])->whereNumber('line');
        Route::post('reconciliations/{bankReconciliation}/lines/{line}/match', [ReconciliationController::class, 'match'])->whereNumber('line');
        Route::post('reconciliations/{bankReconciliation}/lines/{line}/unmatch', [ReconciliationController::class, 'unmatch'])->whereNumber('line');
        Route::post('reconciliations/{bankReconciliation}/lines/{line}/create-entry', [ReconciliationController::class, 'createEntry'])->whereNumber('line');
    });

    Route::middleware('permission:finance.cashbook')->group(function () {
        Route::post('cashbook', [CashbookController::class, 'store']);
        Route::put('cashbook/{cashbookEntry}', [CashbookController::class, 'update']);
        Route::post('cashbook/{cashbookEntry}/post', [CashbookController::class, 'post']);
        Route::post('cashbook/{cashbookEntry}/reverse', [CashbookController::class, 'reverse']);
        Route::post('cashbook/{cashbookEntry}/cancel', [CashbookController::class, 'cancel']);
    });

    Route::middleware('permission:finance.statements')->prefix('statements')->group(function () {
        Route::get('profit-and-loss', [StatementController::class, 'profitAndLoss']);
        Route::get('balance-sheet', [StatementController::class, 'balanceSheet']);
        Route::get('cash-flow', [StatementController::class, 'cashFlow']);
        Route::get('budget-vs-actual', [StatementController::class, 'budgetVsActual']);
    });

    Route::middleware('permission:finance.close')->group(function () {
        Route::post('periods/{period}/close', [PeriodController::class, 'close'])->where('period', '\d{4}-\d{2}');
        Route::post('periods/{period}/reopen', [PeriodController::class, 'reopen'])->where('period', '\d{4}-\d{2}');
        Route::post('years/{year}/close', [PeriodController::class, 'closeYear'])->whereNumber('year');
    });

    Route::put('budgets/{year}', [BudgetController::class, 'update'])->whereNumber('year')->middleware('permission:finance.budget');
});

Route::middleware('module:assets')->prefix('assets')->group(function () {
    Route::middleware('permission:assets.view')->group(function () {
        Route::get('overview', [OverviewController::class, 'assets']);
        Route::get('classes', [AssetClassController::class, 'index']);
        Route::get('register', [FixedAssetController::class, 'index']);
        Route::get('register/{fixedAsset}', [FixedAssetController::class, 'show']);
        Route::get('lookups', [FixedAssetController::class, 'lookups']);
        Route::get('depreciation', [DepreciationController::class, 'index']);
        Route::get('depreciation/{depreciationRun}', [DepreciationController::class, 'show'])->whereNumber('depreciationRun');
    });

    Route::middleware('permission:assets.manage')->group(function () {
        Route::get('class-accounts', [AssetClassController::class, 'accounts']);
        Route::post('classes', [AssetClassController::class, 'store']);
        Route::put('classes/{assetClass}', [AssetClassController::class, 'update']);
        Route::post('register', [FixedAssetController::class, 'store']);
        Route::put('register/{fixedAsset}', [FixedAssetController::class, 'update']);
        Route::delete('register/{fixedAsset}', [FixedAssetController::class, 'destroy']);
        Route::post('register/{fixedAsset}/capitalise', [FixedAssetController::class, 'capitalise']);
        Route::post('register/{fixedAsset}/transfer', [FixedAssetController::class, 'transfer']);
    });

    Route::middleware('permission:assets.depreciate')->group(function () {
        Route::get('depreciation-preview', [DepreciationController::class, 'preview']);
        Route::post('depreciation', [DepreciationController::class, 'store']);
    });

    Route::post('register/{fixedAsset}/dispose', [FixedAssetController::class, 'dispose'])->middleware('permission:assets.dispose');
});
