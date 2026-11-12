<?php

namespace App\Http\Controllers\Api\Erp\Procurement;

use App\Http\Controllers\Controller;
use App\Models\Erp\Procurement\SupplierInvoice;
use App\Services\Erp\Procurement\SupplierInvoices;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class SupplierInvoiceController extends Controller
{
    public function __construct(private readonly SupplierInvoices $invoices, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        $status = $request->query('status');

        return response()->json(SupplierInvoice::query()
            ->with(['supplier:id,code,name', 'order:id,number', 'creator:id,name'])
            ->when($status === 'to_match', fn ($q) => $q->whereIn('status', [SupplierInvoice::STATUS_DRAFT, SupplierInvoice::STATUS_AWAITING_APPROVAL, SupplierInvoice::STATUS_APPROVED]))
            ->when($status === 'unpaid', fn ($q) => $q->where('status', SupplierInvoice::STATUS_POSTED)->whereColumn('amount_paid', '<', 'total'))
            ->when($status && ! in_array($status, ['to_match', 'unpaid'], true), fn ($q) => $q->where('status', $status))
            ->when($request->query('supplier_id'), fn ($q, $v) => $q->where('supplier_id', $v))
            ->when($request->query('purchase_order_id'), fn ($q, $v) => $q->where('purchase_order_id', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")->orWhere('supplier_invoice_number', 'like', "%{$v}%")))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 200)));
    }

    public function show(SupplierInvoice $invoice): JsonResponse
    {
        return response()->json(['data' => $invoice->load(SupplierInvoices::RELATIONS)]);
    }

    public function store(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'purchase_order_id' => ['required', 'integer', Rule::exists('purchase_orders', 'id')->where('company_id', $company)],
            ...$this->rules(),
        ]);

        return response()->json(['data' => $this->invoices->create($data, $request->user())], 201);
    }

    public function update(Request $request, SupplierInvoice $invoice): JsonResponse
    {
        return response()->json(['data' => $this->invoices->update($invoice, $request->validate($this->rules()), $request->user())]);
    }

    public function approve(Request $request, SupplierInvoice $invoice): JsonResponse
    {
        $comment = $request->validate(['comment' => ['nullable', 'string', 'max:500']])['comment'] ?? null;
        $result = $this->invoices->approveVariance($invoice, $request->user(), $comment);

        return response()->json(['message' => "Variance on {$result->number} approved.", 'data' => $result]);
    }

    public function post(Request $request, SupplierInvoice $invoice): JsonResponse
    {
        $result = $this->invoices->post($invoice, $request->user());

        return response()->json(['message' => "{$result->number} posted.", 'data' => $result]);
    }

    public function cancel(Request $request, SupplierInvoice $invoice): JsonResponse
    {
        $result = $this->invoices->cancel($invoice, $request->user());

        return response()->json(['message' => "{$result->number} cancelled.", 'data' => $result]);
    }

    /** @return array<string, mixed> */
    private function rules(): array
    {
        $company = $this->tenant->id();

        return [
            'supplier_invoice_number' => ['required', 'string', 'max:80'],
            'invoice_date' => ['nullable', 'date', 'before_or_equal:today'],
            'due_date' => ['nullable', 'date', 'after_or_equal:invoice_date'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'lines' => ['required', 'array', 'min:1', 'max:200'],
            'lines.*.purchase_order_line_id' => ['required', 'integer', 'distinct'],
            'lines.*.quantity' => ['required', 'numeric', 'gt:0'],
            'lines.*.unit_price' => ['required', 'numeric', 'min:0', 'max:999999999999'],
            'lines.*.vat_rate' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'lines.*.expense_account_id' => ['nullable', 'integer', Rule::exists('accounts', 'id')->where('company_id', $company)],
        ];
    }
}
