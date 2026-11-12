<?php

namespace App\Http\Controllers\Api\Erp\Production;

use App\Http\Controllers\Controller;
use App\Models\Erp\Production\ProductionReceipt;
use App\Models\Erp\Production\QcCheck;
use App\Services\Erp\Production\ProductionOrders;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** The quality-control queue and the check that releases or rejects a batch. */
class QcController extends Controller
{
    public function __construct(private readonly ProductionOrders $orders) {}

    public function index(Request $request): JsonResponse
    {
        $status = $request->query('status', ProductionReceipt::STATUS_PENDING);

        return response()->json(ProductionReceipt::query()
            ->with(['order:id,number,product_id,output_warehouse_id', 'order.product:id,sku,name', 'order.outputWarehouse:id,name',
                'recorder:id,name', 'qc.inspector:id,name'])
            ->when($status !== 'all', fn ($q) => $q->where('status', $status))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")
                ->orWhere('batch_number', 'like', "%{$v}%")))
            ->orderBy($status === ProductionReceipt::STATUS_PENDING ? 'id' : 'updated_at', $status === ProductionReceipt::STATUS_PENDING ? 'asc' : 'desc')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(ProductionReceipt $receipt): JsonResponse
    {
        return response()->json(['data' => $receipt->load(['order.product:id,sku,name', 'recorder:id,name', 'qc.inspector:id,name', 'stockDocument:id,number'])]);
    }

    public function store(Request $request, ProductionReceipt $receipt): JsonResponse
    {
        $data = $request->validate([
            'decision' => ['required', Rule::in([QcCheck::RELEASE, QcCheck::REJECT])],
            'notes' => ['nullable', 'string', 'max:2000'],
            'parameters' => ['required', 'array', 'min:1', 'max:40'],
            'parameters.*.name' => ['required', 'string', 'max:80'],
            'parameters.*.target' => ['nullable', 'string', 'max:80'],
            'parameters.*.value' => ['nullable', 'string', 'max:80'],
            'parameters.*.passed' => ['required', 'boolean'],
        ]);

        $check = $this->orders->inspect($receipt, $data['decision'], $data['parameters'], $request->user(), $data['notes'] ?? null);

        return response()->json([
            'message' => $check->decision === QcCheck::RELEASE ? "{$receipt->number} released into stock." : "{$receipt->number} rejected; nothing entered stock.",
            'data' => $check,
        ], 201);
    }
}
