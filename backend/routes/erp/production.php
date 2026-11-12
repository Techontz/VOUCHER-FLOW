<?php

use App\Http\Controllers\Api\Erp\Production\BomController;
use App\Http\Controllers\Api\Erp\Production\ProductionController;
use App\Http\Controllers\Api\Erp\Production\ProductionOrderController;
use App\Http\Controllers\Api\Erp\Production\QcController;
use App\Http\Controllers\Api\Erp\Production\WorkCentreController;
use Illuminate\Support\Facades\Route;

/*
 * Production & manufacturing, under /api/erp/production. Required inside the
 * authenticated, tenant-scoped ERP group in routes/api.php.
 */
Route::prefix('production')->middleware('module:production')->group(function () {
    Route::middleware('permission:production.view')->group(function () {
        Route::get('overview', [ProductionController::class, 'overview']);
        Route::get('genealogy', [ProductionController::class, 'genealogy']);
        Route::get('options', [ProductionController::class, 'options']);
        Route::get('work-centres', [WorkCentreController::class, 'index']);
        Route::get('boms', [BomController::class, 'index']);
        Route::get('boms/{bom}', [BomController::class, 'show']);
        Route::get('orders', [ProductionOrderController::class, 'index']);
        Route::post('orders/check', [ProductionOrderController::class, 'check']);
        Route::get('orders/{productionOrder}', [ProductionOrderController::class, 'show']);
        Route::get('qc', [QcController::class, 'index']);
        Route::get('receipts/{receipt}', [QcController::class, 'show']);
    });

    Route::middleware('permission:production.manage')->group(function () {
        Route::post('work-centres', [WorkCentreController::class, 'store']);
        Route::put('work-centres/{workCentre}', [WorkCentreController::class, 'update']);
        Route::post('boms', [BomController::class, 'store']);
        Route::put('boms/{bom}', [BomController::class, 'update']);
        Route::delete('boms/{bom}', [BomController::class, 'destroy']);
        Route::post('boms/{bom}/versions', [BomController::class, 'version']);
        Route::post('boms/{bom}/activate', [BomController::class, 'activate']);
    });

    Route::middleware('permission:production.plan')->group(function () {
        Route::post('orders', [ProductionOrderController::class, 'store']);
        Route::put('orders/{productionOrder}', [ProductionOrderController::class, 'update']);
        Route::post('orders/{productionOrder}/release', [ProductionOrderController::class, 'release']);
        Route::post('orders/{productionOrder}/cancel', [ProductionOrderController::class, 'cancel']);
        Route::post('orders/{productionOrder}/complete', [ProductionOrderController::class, 'complete']);
    });

    Route::post('orders/{productionOrder}/issue', [ProductionOrderController::class, 'issue'])->middleware('permission:production.issue');
    Route::post('orders/{productionOrder}/receipts', [ProductionOrderController::class, 'receive'])->middleware('permission:production.receive');
    Route::post('receipts/{receipt}/qc', [QcController::class, 'store'])->middleware('permission:production.qc');
    Route::post('orders/{productionOrder}/close', [ProductionOrderController::class, 'close'])->middleware('permission:production.close');
});
