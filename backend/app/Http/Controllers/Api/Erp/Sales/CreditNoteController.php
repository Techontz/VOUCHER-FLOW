<?php

namespace App\Http\Controllers\Api\Erp\Sales;

use App\Http\Controllers\Controller;
use App\Models\Erp\Sales\SalesCreditNote;
use App\Services\Erp\Sales\SalesCreditNotes;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class CreditNoteController extends Controller
{
    public function __construct(private readonly SalesCreditNotes $notes, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(SalesCreditNote::query()
            ->with(['customer:id,code,name', 'invoice:id,number', 'warehouse:id,name'])
            ->withCount('lines')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")
                ->orWhereHas('customer', fn ($c) => $c->where('name', 'like', "%{$v}%"))))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(SalesCreditNote $creditNote): JsonResponse
    {
        return response()->json(['data' => $creditNote->load([
            'lines.product:id,sku,name,unit_id', 'lines.product.unit:id,code', 'customer', 'invoice:id,number,total',
            'warehouse:id,name', 'stockDocument:id,number,status', 'creator:id,name', 'poster:id,name',
        ])]);
    }

    public function store(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'sales_invoice_id' => ['required', 'integer', Rule::exists('sales_invoices', 'id')->where('company_id', $company)],
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'credit_date' => ['nullable', 'date', 'before_or_equal:today'],
            'return_to_stock' => ['boolean'],
            'warehouse_id' => ['nullable', 'required_if:return_to_stock,true', 'integer', Rule::exists('warehouses', 'id')->where('company_id', $company)],
            'lines' => ['required', 'array', 'min:1'],
            'lines.*.sales_invoice_line_id' => ['required', 'integer'],
            'lines.*.quantity' => ['required', 'numeric', 'min:0'],
            'lines.*.batch_number' => ['nullable', 'string', 'max:60'],
            'lines.*.expiry_date' => ['nullable', 'date'],
        ]);

        $note = $this->notes->create($data, $data['lines'], $request->user());

        return response()->json(['message' => "Credit note {$note->number} prepared.", 'data' => $note], 201);
    }

    public function post(Request $request, SalesCreditNote $creditNote): JsonResponse
    {
        $posted = $this->notes->post($creditNote, $request->user());

        return response()->json(['message' => "{$posted->number} posted.", 'data' => $posted]);
    }

    public function cancel(Request $request, SalesCreditNote $creditNote): JsonResponse
    {
        return response()->json(['message' => "{$creditNote->number} cancelled.", 'data' => $this->notes->cancel($creditNote, $request->user())]);
    }
}
