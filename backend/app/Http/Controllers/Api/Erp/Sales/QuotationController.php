<?php

namespace App\Http\Controllers\Api\Erp\Sales;

use App\Http\Controllers\Controller;
use App\Models\Erp\Sales\SalesQuotation;
use App\Services\Erp\Sales\SalesOrders;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class QuotationController extends Controller
{
    use ValidatesSalesLines;

    public function __construct(private readonly SalesOrders $sales, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(SalesQuotation::query()
            ->with(['customer:id,code,name', 'creator:id,name', 'order:id,number'])
            ->withCount('lines')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('customer_id'), fn ($q, $v) => $q->where('customer_id', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")
                ->orWhereHas('customer', fn ($c) => $c->where('name', 'like', "%{$v}%"))))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(SalesQuotation $quotation): JsonResponse
    {
        return response()->json(['data' => $quotation->load([
            'lines.product:id,sku,name,unit_id', 'lines.product.unit:id,code', 'customer', 'creator:id,name', 'order:id,number,status',
        ])]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->rules($request);

        return response()->json(['data' => $this->sales->saveQuotation(null, $data, $data['lines'], $request->user())], 201);
    }

    public function update(Request $request, SalesQuotation $quotation): JsonResponse
    {
        $data = $this->rules($request);

        return response()->json(['data' => $this->sales->saveQuotation($quotation, $data, $data['lines'], $request->user())]);
    }

    public function send(Request $request, SalesQuotation $quotation): JsonResponse
    {
        return response()->json(['message' => "{$quotation->number} marked as sent.", 'data' => $this->sales->setQuotationStatus($quotation, 'sent', $request->user())]);
    }

    public function reject(Request $request, SalesQuotation $quotation): JsonResponse
    {
        return response()->json(['message' => "{$quotation->number} marked as declined by the customer.", 'data' => $this->sales->setQuotationStatus($quotation, 'rejected', $request->user())]);
    }

    public function cancel(Request $request, SalesQuotation $quotation): JsonResponse
    {
        return response()->json(['message' => "{$quotation->number} cancelled.", 'data' => $this->sales->setQuotationStatus($quotation, 'cancelled', $request->user())]);
    }

    public function convert(Request $request, SalesQuotation $quotation): JsonResponse
    {
        abort_unless($request->user()->hasPermission('sales.order'), 403, 'Your role does not allow you to prepare sales orders.');
        $order = $this->sales->convert($quotation, $request->user());

        return response()->json(['message' => "{$quotation->number} became order {$order->number}.", 'data' => $order], 201);
    }

    private function rules(Request $request): array
    {
        return $this->salesDocument($request, $this->tenant->id(), [
            'quote_date' => ['nullable', 'date'],
            'valid_until' => ['nullable', 'date', 'after_or_equal:quote_date'],
        ]);
    }
}
