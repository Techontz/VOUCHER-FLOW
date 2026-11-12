<?php

use App\Http\Controllers\Api\Erp\Sales;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Sales, and finance verification & dispatch. Required inside the
| authenticated, tenant-scoped `erp` group: paths are under /api/erp.
|--------------------------------------------------------------------------
*/

Route::middleware('module:sales')->prefix('sales')->group(function () {
    Route::middleware('permission:sales.view')->group(function () {
        Route::get('overview', [Sales\SalesReportController::class, 'overview']);
        Route::get('lookups', [Sales\SalesReportController::class, 'lookups']);
        Route::get('prices', [Sales\PriceListController::class, 'prices']);
        Route::get('reports/sales', [Sales\SalesReportController::class, 'sales']);
        Route::get('reports/aged-receivables', [Sales\SalesReportController::class, 'aged']);
        Route::get('customers/{customer}/statement', [Sales\SalesReportController::class, 'statement']);

        Route::get('price-lists', [Sales\PriceListController::class, 'index']);
        Route::get('price-lists/{priceList}', [Sales\PriceListController::class, 'show']);
        Route::get('quotations', [Sales\QuotationController::class, 'index']);
        Route::get('quotations/{quotation}', [Sales\QuotationController::class, 'show']);
        Route::get('orders', [Sales\SalesOrderController::class, 'index']);
        Route::get('orders/counts', [Sales\SalesOrderController::class, 'counts']);
        Route::get('orders/{salesOrder}', [Sales\SalesOrderController::class, 'show']);
        Route::get('invoices', [Sales\InvoiceController::class, 'index']);
        Route::get('invoices/{invoice}', [Sales\InvoiceController::class, 'show']);
        Route::get('receipts', [Sales\ReceiptController::class, 'index']);
        Route::get('receipts/{receipt}', [Sales\ReceiptController::class, 'show']);
        Route::get('credit-notes', [Sales\CreditNoteController::class, 'index']);
        Route::get('credit-notes/{creditNote}', [Sales\CreditNoteController::class, 'show']);
    });

    Route::middleware('permission:sales.pricing')->group(function () {
        Route::post('price-lists', [Sales\PriceListController::class, 'store']);
        Route::put('price-lists/{priceList}', [Sales\PriceListController::class, 'update']);
        Route::delete('price-lists/{priceList}', [Sales\PriceListController::class, 'destroy']);
        Route::put('price-lists/{priceList}/items', [Sales\PriceListController::class, 'items']);
        Route::put('price-lists/{priceList}/customers', [Sales\PriceListController::class, 'customers']);
    });

    Route::middleware('permission:sales.quote')->group(function () {
        Route::post('quotations', [Sales\QuotationController::class, 'store']);
        Route::put('quotations/{quotation}', [Sales\QuotationController::class, 'update']);
        Route::post('quotations/{quotation}/send', [Sales\QuotationController::class, 'send']);
        Route::post('quotations/{quotation}/reject', [Sales\QuotationController::class, 'reject']);
        Route::post('quotations/{quotation}/cancel', [Sales\QuotationController::class, 'cancel']);
        // Also needs sales.order, checked in the controller.
        Route::post('quotations/{quotation}/convert', [Sales\QuotationController::class, 'convert']);
    });

    Route::middleware('permission:sales.order')->group(function () {
        Route::post('orders', [Sales\SalesOrderController::class, 'store']);
        Route::put('orders/{salesOrder}', [Sales\SalesOrderController::class, 'update']);
        Route::post('orders/{salesOrder}/submit', [Sales\SalesOrderController::class, 'submit']);
    });

    Route::middleware('permission:sales.approve')->group(function () {
        Route::post('orders/{salesOrder}/approve', [Sales\SalesOrderController::class, 'approve']);
        Route::post('orders/{salesOrder}/reject', [Sales\SalesOrderController::class, 'reject']);
        Route::post('orders/{salesOrder}/cancel', [Sales\SalesOrderController::class, 'cancel']);
    });

    Route::middleware('permission:sales.invoice')->group(function () {
        Route::post('orders/{salesOrder}/invoice', [Sales\SalesOrderController::class, 'invoice']);
        Route::post('invoices/{invoice}/post', [Sales\InvoiceController::class, 'post']);
        Route::post('invoices/{invoice}/cancel', [Sales\InvoiceController::class, 'cancel']);
    });

    Route::post('receipts', [Sales\ReceiptController::class, 'store'])->middleware('permission:sales.receipt');

    // Finance verification. Lives with sales so a company without the
    // dispatch module still gets its receipts onto the books.
    Route::middleware('permission:dispatch.verify')->group(function () {
        Route::post('receipts/{receipt}/verify', [Sales\ReceiptController::class, 'verify']);
        Route::post('receipts/{receipt}/reject', [Sales\ReceiptController::class, 'reject']);
    });

    Route::middleware('permission:sales.return')->group(function () {
        Route::post('credit-notes', [Sales\CreditNoteController::class, 'store']);
        Route::post('credit-notes/{creditNote}/post', [Sales\CreditNoteController::class, 'post']);
        Route::post('credit-notes/{creditNote}/cancel', [Sales\CreditNoteController::class, 'cancel']);
    });
});

Route::middleware('module:dispatch')->prefix('dispatch')->group(function () {
    Route::middleware('permission:dispatch.view')->group(function () {
        Route::get('lookups', [Sales\LoadingOrderController::class, 'lookups']);
        Route::get('loading-orders', [Sales\LoadingOrderController::class, 'index']);
        Route::get('loading-orders/{loadingOrder}', [Sales\LoadingOrderController::class, 'show']);
    });

    Route::middleware('permission:dispatch.verify')->group(function () {
        Route::get('verification', [Sales\LoadingOrderController::class, 'queue']);
    });

    Route::middleware('permission:dispatch.load')->group(function () {
        Route::post('loading-orders', [Sales\LoadingOrderController::class, 'store']);
        Route::put('loading-orders/{loadingOrder}/loaded', [Sales\LoadingOrderController::class, 'loaded']);
        Route::post('loading-orders/{loadingOrder}/confirm-loading', [Sales\LoadingOrderController::class, 'confirmLoading']);
        Route::post('loading-orders/{loadingOrder}/confirm-driver', [Sales\LoadingOrderController::class, 'confirmDriver']);
        Route::post('loading-orders/{loadingOrder}/delivery-note', [Sales\LoadingOrderController::class, 'deliveryNote']);
        Route::post('loading-orders/{loadingOrder}/cancel', [Sales\LoadingOrderController::class, 'cancel']);
    });

    Route::middleware('permission:dispatch.gatepass')->group(function () {
        Route::post('loading-orders/{loadingOrder}/confirm-security', [Sales\LoadingOrderController::class, 'confirmSecurity']);
        Route::post('loading-orders/{loadingOrder}/gate-pass', [Sales\LoadingOrderController::class, 'gatePass']);
    });

    Route::post('loading-orders/{loadingOrder}/deliver', [Sales\LoadingOrderController::class, 'deliver'])->middleware('permission:dispatch.deliver');
    Route::post('loading-orders/{loadingOrder}/resolve', [Sales\LoadingOrderController::class, 'resolve'])->middleware('permission:dispatch.resolve');
});
