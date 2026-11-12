<?php

use App\Http\Controllers\Api\Erp\Integration\VoucherLinkController;
use Illuminate\Support\Facades\Route;

/*
 * VouchFlow and the ERP: payment vouchers raised from the documents that
 * create a debt, so the company's own approval route governs the payment.
 */
Route::middleware('module:procurement')->group(function () {
    Route::get('procurement/invoices/{supplierInvoice}/voucher', [VoucherLinkController::class, 'forSupplierInvoice'])
        ->middleware('permission:procurement.view');
    Route::post('procurement/invoices/{supplierInvoice}/voucher', [VoucherLinkController::class, 'fromSupplierInvoice'])
        ->middleware('permission:procurement.pay');
});
