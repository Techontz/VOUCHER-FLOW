<?php

namespace App\Http\Controllers\Api\Erp\Sales;

use App\Http\Controllers\Controller;
use App\Models\Erp\Sales\SalesReceipt;
use App\Services\Erp\Sales\SalesReceipts;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Receipts: recorded under sales.receipt, verified under dispatch.verify by someone else. */
class ReceiptController extends Controller
{
    public function __construct(private readonly SalesReceipts $receipts, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(SalesReceipt::query()
            ->with(['customer:id,code,name', 'account:id,code,name', 'creator:id,name', 'verifier:id,name', 'allocations.invoice:id,number,sales_order_id'])
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('customer_id'), fn ($q, $v) => $q->where('customer_id', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")->orWhere('reference', 'like', "%{$v}%")
                ->orWhereHas('customer', fn ($c) => $c->where('name', 'like', "%{$v}%"))))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(SalesReceipt $receipt): JsonResponse
    {
        return response()->json(['data' => $receipt->load(['customer', 'account:id,code,name', 'creator:id,name', 'verifier:id,name', 'allocations.invoice:id,number,total,sales_order_id'])]);
    }

    public function store(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'customer_id' => ['required', 'integer', Rule::exists('customers', 'id')->where('company_id', $company)],
            'account_id' => ['required', 'integer', Rule::exists('accounts', 'id')->where('company_id', $company)],
            'receipt_date' => ['nullable', 'date', 'before_or_equal:today'],
            'method' => ['required', Rule::in(SalesReceipt::METHODS)],
            'reference' => ['nullable', 'string', 'max:80'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'allocations' => ['required', 'array', 'min:1', 'max:100'],
            'allocations.*.sales_invoice_id' => ['required', 'integer', Rule::exists('sales_invoices', 'id')->where('company_id', $company)],
            'allocations.*.amount' => ['required', 'numeric', 'min:0', 'max:9999999999'],
        ]);

        $receipt = $this->receipts->record($data, $data['allocations'], $request->user());

        return response()->json(['message' => "Receipt {$receipt->number} recorded. Someone else in finance must verify it.", 'data' => $receipt], 201);
    }

    public function verify(Request $request, SalesReceipt $receipt): JsonResponse
    {
        $verified = $this->receipts->verify($receipt, $request->user());

        return response()->json(['message' => "{$verified->number} verified and posted.", 'data' => $verified]);
    }

    public function reject(Request $request, SalesReceipt $receipt): JsonResponse
    {
        $reason = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:500']])['reason'];

        return response()->json(['message' => "{$receipt->number} rejected.", 'data' => $this->receipts->reject($receipt, $reason, $request->user())]);
    }
}
