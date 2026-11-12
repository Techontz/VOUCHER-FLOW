<?php

namespace App\Http\Controllers\Api\Erp\Procurement;

use App\Http\Controllers\Controller;
use App\Models\Erp\Procurement\PurchaseRfq;
use App\Services\Erp\Procurement\Rfqs;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class RfqController extends Controller
{
    public function __construct(private readonly Rfqs $rfqs, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(PurchaseRfq::query()
            ->with(['requisition:id,number', 'creator:id,name', 'selectedQuotation:id,supplier_id,total', 'selectedQuotation.supplier:id,name'])
            ->withCount(['lines', 'suppliers', 'quotations'])
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")->orWhere('title', 'like', "%{$v}%")))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(PurchaseRfq $rfq): JsonResponse
    {
        return response()->json(['data' => $rfq->load(Rfqs::RELATIONS)]);
    }

    public function comparison(PurchaseRfq $rfq): JsonResponse
    {
        return response()->json(['data' => $this->rfqs->comparison($rfq)]);
    }

    public function store(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'purchase_requisition_id' => ['nullable', 'integer', Rule::exists('purchase_requisitions', 'id')->where('company_id', $company)],
            'title' => ['required', 'string', 'max:160'],
            'issue_date' => ['nullable', 'date'],
            'closing_date' => ['nullable', 'date', 'after_or_equal:issue_date'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'supplier_ids' => ['required', 'array', 'min:1', 'max:20'],
            'supplier_ids.*' => ['integer', 'distinct', Rule::exists('suppliers', 'id')->where('company_id', $company)],
            'lines' => ['nullable', 'array', 'max:200'],
            'lines.*.line_type' => ['required', Rule::in(['stock', 'service'])],
            'lines.*.product_id' => ['nullable', 'required_if:lines.*.line_type,stock', 'integer', Rule::exists('products', 'id')->where('company_id', $company)],
            'lines.*.description' => ['nullable', 'required_if:lines.*.line_type,service', 'string', 'max:255'],
            'lines.*.quantity' => ['required', 'numeric', 'gt:0'],
            'lines.*.purchase_requisition_line_id' => ['nullable', 'integer'],
            'lines.*.expense_account_id' => ['nullable', 'integer', Rule::exists('accounts', 'id')->where('company_id', $company)],
        ]);

        return response()->json(['data' => $this->rfqs->create($data, $request->user())], 201);
    }

    public function send(Request $request, PurchaseRfq $rfq): JsonResponse
    {
        $result = $this->rfqs->send($rfq, $request->user());

        return response()->json(['message' => "{$result->number} sent to suppliers.", 'data' => $result]);
    }

    public function quote(Request $request, PurchaseRfq $rfq): JsonResponse
    {
        $data = $request->validate([
            'supplier_id' => ['required', 'integer'],
            'reference' => ['nullable', 'string', 'max:80'],
            'quotation_date' => ['nullable', 'date'],
            'valid_until' => ['nullable', 'date'],
            'lead_time_days' => ['nullable', 'integer', 'min:0', 'max:3650'],
            'payment_terms' => ['nullable', 'string', 'max:160'],
            'delivery_terms' => ['nullable', 'string', 'max:160'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'lines' => ['required', 'array', 'min:1'],
            'lines.*.purchase_rfq_line_id' => ['required', 'integer', 'distinct'],
            'lines.*.unit_price' => ['required', 'numeric', 'min:0', 'max:999999999999'],
            'lines.*.vat_rate' => ['nullable', 'numeric', 'min:0', 'max:100'],
        ]);

        return response()->json(['message' => 'Quotation recorded.', 'data' => $this->rfqs->quote($rfq, $data, $request->user())], 201);
    }

    public function award(Request $request, PurchaseRfq $rfq): JsonResponse
    {
        $data = $request->validate([
            'quotation_id' => ['required', 'integer'],
            'reason' => ['required', 'string', 'min:3', 'max:500'],
        ]);
        $result = $this->rfqs->award($rfq, (int) $data['quotation_id'], $data['reason'], $request->user());

        return response()->json(['message' => "{$result->number} awarded.", 'data' => $result]);
    }

    public function cancel(Request $request, PurchaseRfq $rfq): JsonResponse
    {
        $result = $this->rfqs->cancel($rfq, $request->user());

        return response()->json(['message' => "{$result->number} cancelled.", 'data' => $result]);
    }
}
