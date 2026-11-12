<?php

namespace App\Http\Controllers\Api\Erp\Sales;

use App\Http\Controllers\Controller;
use App\Models\Erp\Sales\LoadingOrder;
use App\Models\Erp\Sales\SalesOrder;
use App\Models\Erp\Sales\SalesReceipt;
use App\Models\Erp\Warehouse;
use App\Services\Erp\Sales\Dispatch;
use App\Services\Erp\Sales\SalesOrders;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Finance verification queue and loading orders. Each step is its own
 * endpoint with its own permission, so the warehouse, the driver's handover,
 * the gate and the delivery are each recorded by the person who did them.
 */
class LoadingOrderController extends Controller
{
    public function __construct(private readonly Dispatch $dispatch, private readonly SalesOrders $orders, private readonly TenantContext $tenant) {}

    /** What finance must look at before goods may leave. */
    public function queue(): JsonResponse
    {
        $receipts = SalesReceipt::query()->where('status', SalesReceipt::STATUS_RECORDED)
            ->with(['customer:id,code,name', 'account:id,code,name', 'creator:id,name', 'allocations.invoice:id,number,sales_order_id,total'])
            ->oldest('id')->get();
        $awaiting = SalesOrder::query()->where('status', SalesOrder::STATUS_AWAITING_PAYMENT)
            ->with(['customer:id,code,name', 'invoices' => fn ($q) => $q->where('status', '!=', 'cancelled')->select('id', 'number', 'sales_order_id', 'status', 'total', 'amount_paid')])
            ->oldest('approved_at')->get()
            ->map(fn ($o) => [...$o->toArray(), 'verified_payments' => $this->orders->verifiedPayments($o)]);
        $ready = SalesOrder::query()->where('status', SalesOrder::STATUS_READY)->with('customer:id,code,name')->oldest('approved_at')->limit(50)->get();

        return response()->json(['data' => ['receipts' => $receipts, 'awaiting_payment' => $awaiting, 'ready' => $ready]]);
    }

    public function lookups(): JsonResponse
    {
        return response()->json(['data' => [
            'warehouses' => Warehouse::query()->where('is_active', true)->orderBy('name')->get(['id', 'code', 'name']),
            'ready_orders' => SalesOrder::query()->whereIn('status', [SalesOrder::STATUS_READY, SalesOrder::STATUS_LOADING])
                ->with('customer:id,name')->latest('id')->limit(100)->get(['id', 'number', 'customer_id', 'status', 'warehouse_id', 'delivery_address']),
        ]]);
    }

    public function index(Request $request): JsonResponse
    {
        $stage = $request->query('stage');

        return response()->json(LoadingOrder::query()
            ->with(['customer:id,code,name', 'order:id,number', 'warehouse:id,code,name'])
            ->withCount('lines')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($stage === 'delivery_notes', fn ($q) => $q->whereNotNull('delivery_note_number'))
            ->when($stage === 'gate_passes', fn ($q) => $q->whereNotNull('gate_pass_number'))
            ->when($stage === 'in_transit', fn ($q) => $q->where('status', LoadingOrder::STATUS_DISPATCHED))
            ->when($stage === 'discrepancies', fn ($q) => $q->whereNotNull('discrepancy_status'))
            ->when($request->query('warehouse_id'), fn ($q, $v) => $q->where('warehouse_id', $v))
            ->when($request->query('sales_order_id'), fn ($q, $v) => $q->where('sales_order_id', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")
                ->orWhere('delivery_note_number', 'like', "%{$v}%")->orWhere('gate_pass_number', 'like', "%{$v}%")
                ->orWhere('vehicle_number', 'like', "%{$v}%")->orWhereHas('customer', fn ($c) => $c->where('name', 'like', "%{$v}%"))))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(LoadingOrder $loadingOrder): JsonResponse
    {
        $loading = $this->dispatch->fresh($loadingOrder);

        return response()->json(['data' => [
            ...$loading->toArray(),
            'availability' => $this->dispatch->availability($loading->lines->pluck('product_id')->all()),
            'seller' => ['name' => $this->tenant->company()->name, 'address' => $this->tenant->company()->address, 'phone' => $this->tenant->company()->phone],
        ]]);
    }

    public function store(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'sales_order_id' => ['required', 'integer', Rule::exists('sales_orders', 'id')->where('company_id', $company)],
            'warehouse_id' => ['required', 'integer', Rule::exists('warehouses', 'id')->where('company_id', $company)],
            'planned_date' => ['nullable', 'date'],
            'vehicle_number' => ['nullable', 'string', 'max:40'],
            'driver_name' => ['nullable', 'string', 'max:120'],
            'vehicle_id' => ['nullable', 'integer'],
            'driver_user_id' => ['nullable', 'integer'],
            'destination' => ['nullable', 'string', 'max:255'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'quantities' => ['nullable', 'array'],
            'quantities.*' => ['numeric', 'min:0'],
        ]);

        $order = SalesOrder::query()->findOrFail($data['sales_order_id']);
        $loading = $this->dispatch->create($order, $data, $data['quantities'] ?? [], $request->user());

        return response()->json(['message' => "Loading order {$loading->number} created.", 'data' => $loading], 201);
    }

    public function loaded(Request $request, LoadingOrder $loadingOrder): JsonResponse
    {
        $data = $request->validate(['quantities' => ['required', 'array'], 'quantities.*' => ['nullable', 'numeric']]);

        return response()->json(['message' => 'Loaded quantities saved.', 'data' => $this->dispatch->setLoaded($loadingOrder, $data['quantities'], $request->user())]);
    }

    public function confirmLoading(Request $request, LoadingOrder $loadingOrder): JsonResponse
    {
        $loading = $this->dispatch->confirmLoading($loadingOrder, $request->user());

        return response()->json(['message' => "Loading confirmed; stock issued on {$loading->stockDocument?->number}.", 'data' => $loading]);
    }

    public function confirmDriver(Request $request, LoadingOrder $loadingOrder): JsonResponse
    {
        $name = $request->validate(['name' => ['nullable', 'string', 'max:120']])['name'] ?? null;

        return response()->json(['message' => 'Driver confirmation recorded.', 'data' => $this->dispatch->confirmDriver($loadingOrder, $name, $request->user())]);
    }

    public function confirmSecurity(Request $request, LoadingOrder $loadingOrder): JsonResponse
    {
        $name = $request->validate(['name' => ['nullable', 'string', 'max:120']])['name'] ?? null;

        return response()->json(['message' => 'Security confirmation recorded.', 'data' => $this->dispatch->confirmSecurity($loadingOrder, $name, $request->user())]);
    }

    public function deliveryNote(Request $request, LoadingOrder $loadingOrder): JsonResponse
    {
        $loading = $this->dispatch->issueDeliveryNote($loadingOrder, $request->user());

        return response()->json(['message' => "Delivery note {$loading->delivery_note_number} issued.", 'data' => $loading]);
    }

    public function gatePass(Request $request, LoadingOrder $loadingOrder): JsonResponse
    {
        $loading = $this->dispatch->issueGatePass($loadingOrder, $request->user());

        return response()->json(['message' => "Gate pass {$loading->gate_pass_number} issued.", 'data' => $loading]);
    }

    public function deliver(Request $request, LoadingOrder $loadingOrder): JsonResponse
    {
        $data = $request->validate([
            'received_by_name' => ['required', 'string', 'min:2', 'max:120'],
            'received_date' => ['required', 'date', 'before_or_equal:today'],
            'remark' => ['nullable', 'string', 'max:500'],
            'quantities' => ['required', 'array'],
            'quantities.*' => ['numeric', 'min:0'],
        ]);

        $loading = $this->dispatch->recordDelivery($loadingOrder, $data, $data['quantities'], $request->user());

        return response()->json([
            'message' => $loading->discrepancy_status === 'open' ? 'Delivery recorded with a shortfall. It needs a decision.' : 'Delivery recorded.',
            'data' => $loading,
        ]);
    }

    public function resolve(Request $request, LoadingOrder $loadingOrder): JsonResponse
    {
        $data = $request->validate([
            'decision' => ['required', 'in:return,write_off'],
            'note' => ['required', 'string', 'min:3', 'max:500'],
        ]);

        return response()->json(['message' => 'Discrepancy resolved.', 'data' => $this->dispatch->resolveDiscrepancy($loadingOrder, $data['decision'], $data['note'], $request->user())]);
    }

    public function cancel(Request $request, LoadingOrder $loadingOrder): JsonResponse
    {
        return response()->json(['message' => "{$loadingOrder->number} cancelled.", 'data' => $this->dispatch->cancel($loadingOrder, $request->user())]);
    }
}
