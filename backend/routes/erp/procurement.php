<?php

use App\Http\Controllers\Api\Erp\Procurement;
use Illuminate\Support\Facades\Route;

/*
| Procurement: requisition, quotation, order, receipt, invoice, payment.
| Required inside the authenticated, tenant-scoped /api/erp group. Each route
| names its permission; the services re-check status and separation of duties.
*/
Route::prefix('procurement')->middleware('module:procurement')->group(function () {
    Route::middleware('permission:procurement.view')->group(function () {
        Route::get('overview', [Procurement\OverviewController::class, 'overview']);
        Route::get('lookups', [Procurement\OverviewController::class, 'lookups']);
        Route::get('settings', [Procurement\OverviewController::class, 'settings']);
        Route::get('ageing', [Procurement\OverviewController::class, 'ageing']);
        Route::get('statement/{supplier}', [Procurement\OverviewController::class, 'statement']);

        Route::get('requisitions', [Procurement\RequisitionController::class, 'index']);
        Route::get('requisitions/{requisition}', [Procurement\RequisitionController::class, 'show']);
        Route::get('rfqs', [Procurement\RfqController::class, 'index']);
        Route::get('rfqs/{rfq}', [Procurement\RfqController::class, 'show']);
        Route::get('rfqs/{rfq}/comparison', [Procurement\RfqController::class, 'comparison']);
        Route::get('orders', [Procurement\PurchaseOrderController::class, 'index']);
        Route::get('orders/{order}', [Procurement\PurchaseOrderController::class, 'show']);
        Route::get('invoices', [Procurement\SupplierInvoiceController::class, 'index']);
        Route::get('invoices/{invoice}', [Procurement\SupplierInvoiceController::class, 'show']);
        Route::get('payments', [Procurement\SupplierPaymentController::class, 'index']);
        Route::get('payments/{payment}', [Procurement\SupplierPaymentController::class, 'show']);
    });

    Route::put('settings', [Procurement\OverviewController::class, 'updateSettings'])->middleware('permission:erp.configure');

    Route::middleware('permission:procurement.request')->group(function () {
        Route::post('requisitions', [Procurement\RequisitionController::class, 'store']);
        Route::put('requisitions/{requisition}', [Procurement\RequisitionController::class, 'update']);
        Route::post('requisitions/{requisition}/submit', [Procurement\RequisitionController::class, 'submit']);
        Route::post('requisitions/{requisition}/cancel', [Procurement\RequisitionController::class, 'cancel']);
    });

    Route::middleware('permission:procurement.approve')->group(function () {
        Route::post('requisitions/{requisition}/approve', [Procurement\RequisitionController::class, 'approve']);
        Route::post('requisitions/{requisition}/reject', [Procurement\RequisitionController::class, 'reject']);
        Route::post('orders/{order}/approve', [Procurement\PurchaseOrderController::class, 'approve']);
        Route::post('orders/{order}/reject', [Procurement\PurchaseOrderController::class, 'reject']);
        Route::post('invoices/{invoice}/approve', [Procurement\SupplierInvoiceController::class, 'approve']);
    });

    Route::middleware('permission:procurement.quote')->group(function () {
        Route::post('rfqs', [Procurement\RfqController::class, 'store']);
        Route::post('rfqs/{rfq}/send', [Procurement\RfqController::class, 'send']);
        Route::post('rfqs/{rfq}/quotations', [Procurement\RfqController::class, 'quote']);
        Route::post('rfqs/{rfq}/award', [Procurement\RfqController::class, 'award']);
        Route::post('rfqs/{rfq}/cancel', [Procurement\RfqController::class, 'cancel']);
    });

    Route::middleware('permission:procurement.order')->group(function () {
        Route::post('orders', [Procurement\PurchaseOrderController::class, 'store']);
        Route::put('orders/{order}', [Procurement\PurchaseOrderController::class, 'update']);
        Route::post('orders/{order}/submit', [Procurement\PurchaseOrderController::class, 'submit']);
        Route::post('orders/{order}/send', [Procurement\PurchaseOrderController::class, 'send']);
        Route::post('orders/{order}/close', [Procurement\PurchaseOrderController::class, 'close']);
        Route::post('orders/{order}/cancel', [Procurement\PurchaseOrderController::class, 'cancel']);
    });

    Route::middleware('permission:procurement.receive')->group(function () {
        Route::post('orders/{order}/receive', [Procurement\PurchaseOrderController::class, 'receive']);
        Route::post('orders/{order}/confirm-service', [Procurement\PurchaseOrderController::class, 'confirmService']);
    });

    Route::middleware('permission:procurement.invoice')->group(function () {
        Route::post('invoices', [Procurement\SupplierInvoiceController::class, 'store']);
        Route::put('invoices/{invoice}', [Procurement\SupplierInvoiceController::class, 'update']);
        Route::post('invoices/{invoice}/post', [Procurement\SupplierInvoiceController::class, 'post']);
        Route::post('invoices/{invoice}/cancel', [Procurement\SupplierInvoiceController::class, 'cancel']);
    });

    Route::middleware('permission:procurement.pay')->group(function () {
        Route::post('payments', [Procurement\SupplierPaymentController::class, 'store']);
        Route::post('payments/{payment}/post', [Procurement\SupplierPaymentController::class, 'post']);
        Route::post('payments/{payment}/cancel', [Procurement\SupplierPaymentController::class, 'cancel']);
    });
});
