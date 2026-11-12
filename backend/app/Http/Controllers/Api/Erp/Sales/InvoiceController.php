<?php

namespace App\Http\Controllers\Api\Erp\Sales;

use App\Http\Controllers\Controller;
use App\Models\Erp\Sales\SalesInvoice;
use App\Services\Erp\Sales\SalesInvoices;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class InvoiceController extends Controller
{
    public function __construct(private readonly SalesInvoices $invoices, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(SalesInvoice::query()
            ->with(['customer:id,code,name', 'order:id,number'])
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('customer_id'), fn ($q, $v) => $q->where('customer_id', $v))
            ->when($request->boolean('open_only'), fn ($q) => $q->where('status', SalesInvoice::STATUS_POSTED)->whereRaw('total - amount_paid - amount_credited > 0.004'))
            ->when($request->boolean('overdue'), fn ($q) => $q->where('status', SalesInvoice::STATUS_POSTED)->whereDate('due_date', '<', now()->toDateString())->whereRaw('total - amount_paid - amount_credited > 0.004'))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")
                ->orWhereHas('customer', fn ($c) => $c->where('name', 'like', "%{$v}%"))))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 200)));
    }

    public function show(SalesInvoice $invoice): JsonResponse
    {
        $company = $this->tenant->company();

        return response()->json(['data' => [
            ...$invoice->load([
                'lines.product:id,sku,name,unit_id', 'lines.product.unit:id,code', 'customer', 'order:id,number,delivery_address',
                'loadingOrder:id,number,delivery_note_number', 'creator:id,name', 'poster:id,name',
                'allocations.receipt:id,number,receipt_date,status,method',
                'creditNotes' => fn ($q) => $q->where('status', '!=', 'cancelled')->select('id', 'number', 'sales_invoice_id', 'credit_date', 'status', 'total'),
            ])->toArray(),
            'seller' => [
                'name' => $company->name, 'email' => $company->email, 'phone' => $company->phone ?? null,
                'address' => $company->address ?? null, 'city' => $company->city ?? null, 'tin' => $company->tin ?? null,
                'logo_path' => $company->logo_path ?? null,
                'currency' => BusinessConfig::of($company)->setting('base_currency'),
            ],
        ]]);
    }

    public function post(Request $request, SalesInvoice $invoice): JsonResponse
    {
        $posted = $this->invoices->post($invoice, $request->user());

        return response()->json(['message' => "{$posted->number} posted.", 'data' => $posted]);
    }

    public function cancel(Request $request, SalesInvoice $invoice): JsonResponse
    {
        return response()->json(['message' => "{$invoice->number} cancelled.", 'data' => $this->invoices->cancel($invoice, $request->user())]);
    }
}
