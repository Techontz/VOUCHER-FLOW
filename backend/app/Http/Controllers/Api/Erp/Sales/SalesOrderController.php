<?php

namespace App\Http\Controllers\Api\Erp\Sales;

use App\Http\Controllers\Controller;
use App\Models\Erp\Sales\LoadingOrder;
use App\Models\Erp\Sales\SalesOrder;
use App\Models\Erp\Warehouse;
use App\Services\Erp\Sales\Dispatch;
use App\Services\Erp\Sales\SalesInvoices;
use App\Services\Erp\Sales\SalesOrders;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Sales orders. Preparing, approving and invoicing are separate permissions,
 * checked by the route; the service re-checks the order's state every time.
 */
class SalesOrderController extends Controller
{
    use ValidatesSalesLines;

    public function __construct(
        private readonly SalesOrders $sales,
        private readonly SalesInvoices $invoices,
        private readonly Dispatch $dispatch,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $statuses = array_filter(explode(',', (string) $request->query('status')));

        return response()->json(SalesOrder::query()
            ->with(['customer:id,code,name,requires_prepayment', 'creator:id,name', 'warehouse:id,name'])
            ->withCount('lines')
            ->when($statuses, fn ($q) => $q->whereIn('status', $statuses))
            ->when($request->query('customer_id'), fn ($q, $v) => $q->where('customer_id', $v))
            ->when($request->query('payment_mode'), fn ($q, $v) => $q->where('payment_mode', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")
                ->orWhereHas('customer', fn ($c) => $c->where('name', 'like', "%{$v}%"))))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function counts(): JsonResponse
    {
        return response()->json(['data' => SalesOrder::query()->selectRaw('status, COUNT(*) as n')->groupBy('status')->pluck('n', 'status')]);
    }

    public function show(SalesOrder $salesOrder): JsonResponse
    {
        $order = $salesOrder->load([
            'lines.product:id,sku,name,unit_id,track_batches', 'lines.product.unit:id,code',
            'customer', 'warehouse:id,code,name', 'quotation:id,number', 'creator:id,name', 'approver:id,name', 'overrider:id,name',
            'invoices' => fn ($q) => $q->latest('id'),
            'loadingOrders' => fn ($q) => $q->latest('id')->with('warehouse:id,name'),
        ]);
        $productIds = $order->lines->pluck('product_id')->all();

        return response()->json(['data' => [
            ...$order->toArray(),
            'verified_payments' => $this->sales->verifiedPayments($order),
            'remaining_to_load' => $this->sales->remainingToLoad($order),
            'policy_preview' => $order->status === SalesOrder::STATUS_SUBMITTED ? $this->sales->policyPreview($order) : null,
            'availability' => $this->dispatch->availability($productIds),
            'warehouses' => Warehouse::query()->where('is_active', true)->orderBy('name')->get(['id', 'code', 'name']),
        ]]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->rules($request);

        return response()->json(['data' => $this->sales->saveOrder(null, $data, $data['lines'], $request->user())], 201);
    }

    public function update(Request $request, SalesOrder $salesOrder): JsonResponse
    {
        $data = $this->rules($request);

        return response()->json(['data' => $this->sales->saveOrder($salesOrder, $data, $data['lines'], $request->user())]);
    }

    public function submit(Request $request, SalesOrder $salesOrder): JsonResponse
    {
        return response()->json(['message' => "{$salesOrder->number} submitted for approval.", 'data' => $this->sales->submit($salesOrder, $request->user())]);
    }

    public function approve(Request $request, SalesOrder $salesOrder): JsonResponse
    {
        $data = $request->validate([
            'quantities' => ['nullable', 'array'],
            'quantities.*' => ['numeric', 'min:0'],
            'override_reason' => ['nullable', 'string', 'min:5', 'max:500'],
        ]);
        $order = $this->sales->approve($salesOrder, $request->user(), $data['quantities'] ?? [], $data['override_reason'] ?? null);
        $message = $order->status === SalesOrder::STATUS_AWAITING_PAYMENT
            ? "{$order->number} approved. It waits for payment verification before loading."
            : "{$order->number} approved and released for loading.";

        return response()->json(['message' => $message, 'data' => $order]);
    }

    public function reject(Request $request, SalesOrder $salesOrder): JsonResponse
    {
        $reason = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:500']])['reason'];

        return response()->json(['message' => "{$salesOrder->number} rejected.", 'data' => $this->sales->reject($salesOrder, $reason, $request->user())]);
    }

    public function cancel(Request $request, SalesOrder $salesOrder): JsonResponse
    {
        return response()->json(['message' => "{$salesOrder->number} cancelled.", 'data' => $this->sales->cancel($salesOrder, $request->user())]);
    }

    /** Raises a draft invoice for what was approved, or for one delivery. */
    public function invoice(Request $request, SalesOrder $salesOrder): JsonResponse
    {
        $data = $request->validate([
            'loading_order_id' => ['nullable', 'integer', Rule::exists('loading_orders', 'id')->where('company_id', $this->tenant->id())],
            'invoice_date' => ['nullable', 'date'],
        ]);
        $delivery = isset($data['loading_order_id']) ? LoadingOrder::query()->with('lines')->findOrFail($data['loading_order_id']) : null;
        $invoice = $this->invoices->fromOrder($salesOrder, $request->user(), $delivery, $data['invoice_date'] ?? null);

        return response()->json(['message' => "Invoice {$invoice->number} prepared.", 'data' => $invoice], 201);
    }

    private function rules(Request $request): array
    {
        $company = $this->tenant->id();

        return $this->salesDocument($request, $company, [
            'order_date' => ['nullable', 'date'],
            'required_date' => ['nullable', 'date'],
            'warehouse_id' => ['nullable', 'integer', Rule::exists('warehouses', 'id')->where('company_id', $company)->where('is_active', true)],
            'delivery_address' => ['nullable', 'string', 'max:255'],
        ]);
    }
}
