<?php

namespace App\Http\Controllers\Api\Erp\Integration;

use App\Http\Controllers\Controller;
use App\Models\Erp\Procurement\SupplierInvoice;
use App\Services\Erp\VoucherLedger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Raising VouchFlow payment vouchers from the books. */
class VoucherLinkController extends Controller
{
    public function __construct(private readonly VoucherLedger $ledger) {}

    /** A draft voucher for what is still owed on a posted supplier invoice. */
    public function fromSupplierInvoice(Request $request, SupplierInvoice $supplierInvoice): JsonResponse
    {
        $voucher = $this->ledger->raiseFromSupplierInvoice($supplierInvoice, $request->user());

        return response()->json(['data' => ['id' => $voucher->id, 'number' => $voucher->number]], 201);
    }

    /** The voucher in progress for a supplier invoice, so its page can link to it. */
    public function forSupplierInvoice(SupplierInvoice $supplierInvoice): JsonResponse
    {
        $voucher = $this->ledger->openVoucherFor(VoucherLedger::SOURCE_SUPPLIER_INVOICE, $supplierInvoice->id);

        return response()->json(['data' => $voucher ? [
            'id' => $voucher->id, 'number' => $voucher->number, 'status' => $voucher->status,
        ] : null]);
    }
}
