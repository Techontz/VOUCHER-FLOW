<?php

namespace App\Http\Controllers\Api\Erp;

use App\Http\Controllers\Controller;
use App\Models\Erp\Supplier;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class SupplierController extends Controller
{
    public function __construct(private readonly TenantContext $tenant, private readonly AuditLogger $audit) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(Supplier::query()
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                ->where('name', 'like', "%{$v}%")->orWhere('code', 'like', "%{$v}%")->orWhere('phone', 'like', "%{$v}%")))
            ->when($request->query('category'), fn ($q, $v) => $q->where('category', $v))
            ->when($request->boolean('active_only'), fn ($q) => $q->where('is_active', true))
            ->orderBy('name')
            ->paginate(min((int) $request->query('per_page', 50), 200)));
    }

    public function show(Supplier $supplier): JsonResponse
    {
        return response()->json(['data' => $supplier]);
    }

    public function store(Request $request, DocumentNumberer $numbers): JsonResponse
    {
        $data = $this->rules($request);
        $data['code'] ??= $numbers->next('SUP');

        $supplier = Supplier::create([...$data, 'created_by' => $request->user()->id]);
        $this->audit->log('supplier.created', "Added supplier {$supplier->name}", $supplier);

        return response()->json(['data' => $supplier], 201);
    }

    public function update(Request $request, Supplier $supplier): JsonResponse
    {
        $data = array_filter($this->rules($request, $supplier->id), fn ($v, $k) => $k !== 'code' || $v !== null, ARRAY_FILTER_USE_BOTH);
        $before = $supplier->only(array_keys($data));
        $supplier->update($data);
        $this->audit->log('supplier.updated', "Updated supplier {$supplier->name}", $supplier, $before, $supplier->only(array_keys($data)));

        return response()->json(['data' => $supplier]);
    }

    public function destroy(Supplier $supplier): JsonResponse
    {
        $supplier->delete();
        $this->audit->log('supplier.deleted', "Archived supplier {$supplier->name}", $supplier);

        return response()->json(['message' => "{$supplier->name} archived."]);
    }

    private function rules(Request $request, ?int $ignore = null): array
    {
        return $request->validate([
            'code' => ['nullable', 'string', 'max:30', Rule::unique('suppliers')->where('company_id', $this->tenant->id())->ignore($ignore)],
            'name' => [$ignore ? 'sometimes' : 'required', 'string', 'max:180'],
            'contact_person' => ['nullable', 'string', 'max:120'],
            'phone' => ['nullable', 'string', 'max:40'],
            'email' => ['nullable', 'email', 'max:180'],
            'tin' => ['nullable', 'string', 'max:40'],
            'address' => ['nullable', 'string', 'max:255'],
            'city' => ['nullable', 'string', 'max:120'],
            'category' => ['nullable', 'string', 'max:60'],
            'payment_terms_days' => ['sometimes', 'integer', 'min:0', 'max:365'],
            'bank_name' => ['nullable', 'string', 'max:120'],
            'bank_account_name' => ['nullable', 'string', 'max:180'],
            'bank_account_number' => ['nullable', 'string', 'max:60'],
            'custom_fields' => ['nullable', 'array'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
    }
}
