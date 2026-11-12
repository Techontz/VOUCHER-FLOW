<?php

namespace App\Http\Controllers\Api\Erp\Procurement;

use App\Http\Controllers\Controller;
use App\Models\Erp\Procurement\PurchaseRequisition;
use App\Services\Erp\Procurement\Requisitions;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class RequisitionController extends Controller
{
    public function __construct(private readonly Requisitions $requisitions, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(PurchaseRequisition::query()
            ->with(['department:id,name', 'requester:id,name'])
            ->withCount('lines')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('department_id'), fn ($q, $v) => $q->where('department_id', $v))
            ->when($request->boolean('mine'), fn ($q) => $q->where('requested_by', $request->user()->id))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")->orWhere('justification', 'like', "%{$v}%")))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(PurchaseRequisition $requisition): JsonResponse
    {
        return response()->json(['data' => $requisition->load(Requisitions::RELATIONS)]);
    }

    public function store(Request $request): JsonResponse
    {
        return response()->json(['data' => $this->requisitions->create($this->rules($request), $request->user())], 201);
    }

    public function update(Request $request, PurchaseRequisition $requisition): JsonResponse
    {
        return response()->json(['data' => $this->requisitions->update($requisition, $this->rules($request), $request->user())]);
    }

    public function submit(Request $request, PurchaseRequisition $requisition): JsonResponse
    {
        $result = $this->requisitions->submit($requisition, $request->user());

        return response()->json(['message' => "{$result->number} submitted for approval.", 'data' => $result]);
    }

    public function approve(Request $request, PurchaseRequisition $requisition): JsonResponse
    {
        $comment = $request->validate(['comment' => ['nullable', 'string', 'max:500']])['comment'] ?? null;
        $result = $this->requisitions->approve($requisition, $request->user(), $comment);

        return response()->json([
            'message' => $result->status === PurchaseRequisition::STATUS_APPROVED ? "{$result->number} approved." : "First approval recorded; {$result->number} now needs a senior approver.",
            'data' => $result,
        ]);
    }

    public function reject(Request $request, PurchaseRequisition $requisition): JsonResponse
    {
        $comment = $request->validate(['comment' => ['required', 'string', 'min:3', 'max:500']])['comment'];
        $result = $this->requisitions->reject($requisition, $request->user(), $comment);

        return response()->json(['message' => "{$result->number} rejected.", 'data' => $result]);
    }

    public function cancel(Request $request, PurchaseRequisition $requisition): JsonResponse
    {
        $result = $this->requisitions->cancel($requisition, $request->user());

        return response()->json(['message' => "{$result->number} cancelled.", 'data' => $result]);
    }

    private function rules(Request $request): array
    {
        $company = $this->tenant->id();

        return $request->validate([
            'department_id' => ['nullable', 'integer', Rule::exists('departments', 'id')->where('company_id', $company)],
            'needed_by' => ['nullable', 'date'],
            'justification' => ['required', 'string', 'min:5', 'max:2000'],
            'lines' => ['required', 'array', 'min:1', 'max:200'],
            'lines.*.line_type' => ['required', Rule::in(['stock', 'service'])],
            'lines.*.product_id' => ['nullable', 'required_if:lines.*.line_type,stock', 'integer', Rule::exists('products', 'id')->where('company_id', $company)],
            'lines.*.description' => ['nullable', 'required_if:lines.*.line_type,service', 'string', 'max:255'],
            'lines.*.quantity' => ['required', 'numeric', 'gt:0', 'max:999999999'],
            'lines.*.estimated_unit_price' => ['nullable', 'numeric', 'min:0', 'max:999999999999'],
            'lines.*.expense_account_id' => ['nullable', 'integer', Rule::exists('accounts', 'id')->where('company_id', $company)],
        ]);
    }
}
