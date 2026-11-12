<?php

namespace App\Http\Controllers\Api\Erp\Procurement;

use App\Http\Controllers\Controller;
use App\Models\Erp\Procurement\PurchaseOrder;
use App\Services\Erp\Procurement\PurchaseOrders;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class PurchaseOrderController extends Controller
{
    public function __construct(private readonly PurchaseOrders $orders, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        $status = $request->query('status');

        return response()->json(PurchaseOrder::query()
            ->with(['supplier:id,code,name', 'creator:id,name', 'requisition:id,number'])
            ->withCount('lines')
            ->withSum('lines as ordered_quantity', 'quantity')
            ->withSum('lines as received_quantity', 'received_quantity')
            ->when($status === 'to_receive', fn ($q) => $q->whereIn('status', PurchaseOrder::RECEIVABLE))
            ->when($status && $status !== 'to_receive', fn ($q) => $q->where('status', $status))
            ->when($request->query('supplier_id'), fn ($q, $v) => $q->where('supplier_id', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where('number', 'like', "%{$v}%"))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(PurchaseOrder $order): JsonResponse
    {
        return response()->json(['data' => $order->load(PurchaseOrders::RELATIONS)]);
    }

    public function store(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'supplier_quotation_id' => ['nullable', 'integer', Rule::exists('supplier_quotations', 'id')->where('company_id', $company)],
            'purchase_requisition_id' => ['nullable', 'integer', Rule::exists('purchase_requisitions', 'id')->where('company_id', $company)],
            'supplier_id' => ['required_without:supplier_quotation_id', 'nullable', 'integer', Rule::exists('suppliers', 'id')->where('company_id', $company)],
            ...$this->rules($request, ! $request->filled('supplier_quotation_id')),
        ]);

        return response()->json(['data' => $this->orders->create($data, $request->user())], 201);
    }

    public function update(Request $request, PurchaseOrder $order): JsonResponse
    {
        return response()->json(['data' => $this->orders->update($order, $request->validate($this->rules($request, true)), $request->user())]);
    }

    public function submit(Request $request, PurchaseOrder $order): JsonResponse
    {
        $result = $this->orders->submit($order, $request->user());

        return response()->json(['message' => "{$result->number} submitted for approval.", 'data' => $result]);
    }

    public function approve(Request $request, PurchaseOrder $order): JsonResponse
    {
        $comment = $request->validate(['comment' => ['nullable', 'string', 'max:500']])['comment'] ?? null;
        $result = $this->orders->approve($order, $request->user(), $comment);

        return response()->json([
            'message' => $result->status === PurchaseOrder::STATUS_APPROVED ? "{$result->number} approved." : "First approval recorded; {$result->number} now needs a senior approver.",
            'data' => $result,
        ]);
    }

    public function reject(Request $request, PurchaseOrder $order): JsonResponse
    {
        $comment = $request->validate(['comment' => ['required', 'string', 'min:3', 'max:500']])['comment'];
        $result = $this->orders->reject($order, $request->user(), $comment);

        return response()->json(['message' => "{$result->number} returned to draft.", 'data' => $result]);
    }

    public function send(Request $request, PurchaseOrder $order): JsonResponse
    {
        $result = $this->orders->send($order, $request->user());

        return response()->json(['message' => "{$result->number} marked as sent to the supplier.", 'data' => $result]);
    }

    public function receive(Request $request, PurchaseOrder $order): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'warehouse_id' => ['nullable', 'integer', Rule::exists('warehouses', 'id')->where('company_id', $company)],
            'received_date' => ['nullable', 'date', 'before_or_equal:today'],
            'delivery_note' => ['nullable', 'string', 'max:60'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'lines' => ['required', 'array', 'min:1'],
            'lines.*.purchase_order_line_id' => ['required', 'integer'],
            'lines.*.quantity' => ['required', 'numeric', 'min:0'],
            'lines.*.batch_number' => ['nullable', 'string', 'max:60'],
            'lines.*.expiry_date' => ['nullable', 'date'],
            'lines.*.serial_number' => ['nullable', 'string', 'max:80'],
        ]);
        $receipt = $this->orders->receive($order, $data, $request->user());

        return response()->json(['message' => "Goods received with {$receipt->number}.", 'data' => $receipt], 201);
    }

    public function confirmService(Request $request, PurchaseOrder $order): JsonResponse
    {
        $data = $request->validate([
            'received_date' => ['nullable', 'date', 'before_or_equal:today'],
            'delivery_note' => ['nullable', 'string', 'max:60'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'lines' => ['required', 'array', 'min:1'],
            'lines.*.purchase_order_line_id' => ['required', 'integer'],
            'lines.*.quantity' => ['required', 'numeric', 'min:0'],
        ]);
        $receipt = $this->orders->confirmService($order, $data, $request->user());

        return response()->json(['message' => "Service confirmed with {$receipt->number}.", 'data' => $receipt], 201);
    }

    public function close(Request $request, PurchaseOrder $order): JsonResponse
    {
        $result = $this->orders->close($order, $request->user());

        return response()->json(['message' => "{$result->number} closed.", 'data' => $result]);
    }

    public function cancel(Request $request, PurchaseOrder $order): JsonResponse
    {
        $reason = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:255']])['reason'];
        $result = $this->orders->cancel($order, $reason, $request->user());

        return response()->json(['message' => "{$result->number} cancelled.", 'data' => $result]);
    }

    /** @return array<string, mixed> */
    private function rules(Request $request, bool $linesRequired): array
    {
        $company = $this->tenant->id();

        return [
            'warehouse_id' => ['nullable', 'integer', Rule::exists('warehouses', 'id')->where('company_id', $company)],
            'order_date' => ['nullable', 'date'],
            'expected_date' => ['nullable', 'date'],
            'payment_terms' => ['nullable', 'string', 'max:160'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'lines' => [$linesRequired ? 'required' : 'nullable', 'array', 'max:200'],
            'lines.*.line_type' => ['required', Rule::in(['stock', 'service'])],
            'lines.*.product_id' => ['nullable', 'required_if:lines.*.line_type,stock', 'integer', Rule::exists('products', 'id')->where('company_id', $company)],
            'lines.*.description' => ['nullable', 'required_if:lines.*.line_type,service', 'string', 'max:255'],
            'lines.*.quantity' => ['required', 'numeric', 'gt:0', 'max:999999999'],
            'lines.*.unit_price' => ['required', 'numeric', 'min:0', 'max:999999999999'],
            'lines.*.vat_rate' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'lines.*.purchase_requisition_line_id' => ['nullable', 'integer'],
            'lines.*.expense_account_id' => ['nullable', 'integer', Rule::exists('accounts', 'id')->where('company_id', $company)],
        ];
    }
}
