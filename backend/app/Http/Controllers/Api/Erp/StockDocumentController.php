<?php

namespace App\Http\Controllers\Api\Erp;

use App\Http\Controllers\Controller;
use App\Models\Erp\StockDocument;
use App\Services\Erp\StockDocuments;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Goods received, issues, transfers, adjustments, counts and opening stock.
 *
 * Preparing a document and posting it are separate permissions, so the person
 * who keys a GRN need not be the person who puts it on the books.
 */
class StockDocumentController extends Controller
{
    /** The permission that prepares each type of document. */
    private const PREPARE = [
        StockDocument::TYPE_OPENING => 'inventory.receive',
        StockDocument::TYPE_GRN => 'inventory.receive',
        StockDocument::TYPE_ISSUE => 'inventory.issue',
        StockDocument::TYPE_TRANSFER => 'inventory.transfer',
        StockDocument::TYPE_ADJUSTMENT => 'inventory.adjust',
        StockDocument::TYPE_COUNT => 'inventory.adjust',
    ];

    public function __construct(private readonly StockDocuments $documents, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(StockDocument::query()
            ->with(['warehouse:id,code,name', 'toWarehouse:id,code,name', 'supplier:id,name', 'creator:id,name'])
            ->withCount('lines')
            ->when($request->query('type'), fn ($q, $v) => $q->where('type', $v))
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('warehouse_id'), fn ($q, $v) => $q->where(fn ($w) => $w->where('warehouse_id', $v)->orWhere('to_warehouse_id', $v)))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")->orWhere('reference', 'like', "%{$v}%")))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(StockDocument $stockDocument): JsonResponse
    {
        return response()->json(['data' => $stockDocument->load([
            'lines.product:id,sku,name,unit_id,track_batches,track_expiry,track_serials', 'lines.product.unit:id,code,name',
            'warehouse', 'toWarehouse', 'supplier:id,code,name', 'creator:id,name', 'poster:id,name',
            'reversalOf:id,number', 'movements.warehouse:id,name',
        ])]);
    }

    public function store(Request $request): JsonResponse
    {
        $type = $request->validate(['type' => ['required', Rule::in(StockDocument::TYPES)]])['type'];
        $this->authorizeType($request, $type);
        $data = $this->rules($request);

        return response()->json(['data' => $this->documents->create($type, $data, $data['lines'], $request->user())], 201);
    }

    public function update(Request $request, StockDocument $stockDocument): JsonResponse
    {
        $this->authorizeType($request, $stockDocument->type);
        $data = $this->rules($request);

        return response()->json(['data' => $this->documents->update($stockDocument, $data, $data['lines'], $request->user())]);
    }

    public function post(Request $request, StockDocument $stockDocument): JsonResponse
    {
        $document = $this->documents->post($stockDocument, $request->user());

        return response()->json(['message' => "{$document->number} posted.", 'data' => $document]);
    }

    public function reverse(Request $request, StockDocument $stockDocument): JsonResponse
    {
        $reason = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:255']])['reason'];
        $reversal = $this->documents->reverse($stockDocument, $reason, $request->user());

        return response()->json(['message' => "{$stockDocument->number} reversed by {$reversal->number}.", 'data' => $reversal]);
    }

    public function cancel(Request $request, StockDocument $stockDocument): JsonResponse
    {
        $this->authorizeType($request, $stockDocument->type);

        return response()->json(['message' => 'Draft cancelled.', 'data' => $this->documents->cancel($stockDocument, $request->user())]);
    }

    private function authorizeType(Request $request, string $type): void
    {
        abort_unless($request->user()->hasPermission(self::PREPARE[$type]), 403, 'Your role does not allow you to prepare this kind of stock document.');
    }

    private function rules(Request $request): array
    {
        $company = $this->tenant->id();
        $warehouse = Rule::exists('warehouses', 'id')->where('company_id', $company)->where('is_active', true);

        return $request->validate([
            'document_date' => ['nullable', 'date', 'before_or_equal:today'],
            'warehouse_id' => ['required', 'integer', $warehouse],
            'to_warehouse_id' => ['nullable', 'integer', $warehouse],
            'supplier_id' => ['nullable', 'integer', Rule::exists('suppliers', 'id')->where('company_id', $company)],
            'reference' => ['nullable', 'string', 'max:80'],
            'reason' => ['nullable', 'string', 'max:255'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'lines' => ['required', 'array', 'min:1', 'max:500'],
            'lines.*.product_id' => ['required', 'integer', Rule::exists('products', 'id')->where('company_id', $company)],
            'lines.*.quantity' => ['required', 'numeric', 'between:-999999999,999999999'],
            'lines.*.unit_cost' => ['nullable', 'numeric', 'min:0'],
            'lines.*.batch_number' => ['nullable', 'string', 'max:60'],
            'lines.*.expiry_date' => ['nullable', 'date'],
            'lines.*.serial_number' => ['nullable', 'string', 'max:80'],
            'lines.*.note' => ['nullable', 'string', 'max:255'],
        ]);
    }
}
