<?php

namespace App\Http\Controllers\Api\Erp\Procurement;

use App\Http\Controllers\Controller;
use App\Models\Erp\Procurement\SupplierPayment;
use App\Services\Erp\Procurement\SupplierPayments;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class SupplierPaymentController extends Controller
{
    public function __construct(private readonly SupplierPayments $payments, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(SupplierPayment::query()
            ->with(['supplier:id,code,name', 'account:id,code,name', 'creator:id,name'])
            ->withCount('allocations')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('supplier_id'), fn ($q, $v) => $q->where('supplier_id', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")->orWhere('reference', 'like', "%{$v}%")))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(SupplierPayment $payment): JsonResponse
    {
        return response()->json(['data' => $payment->load(SupplierPayments::RELATIONS)]);
    }

    /** `post: true` prepares and posts in one step, still as two audited acts. */
    public function store(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'supplier_id' => ['required', 'integer', Rule::exists('suppliers', 'id')->where('company_id', $company)],
            'account_id' => ['required', 'integer', Rule::exists('accounts', 'id')->where('company_id', $company)],
            'payment_date' => ['nullable', 'date', 'before_or_equal:today'],
            'method' => ['nullable', Rule::in(SupplierPayment::METHODS)],
            'reference' => ['nullable', 'string', 'max:80'],
            'amount' => ['required', 'numeric', 'gt:0', 'max:999999999999'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'allocations' => ['required', 'array', 'min:1', 'max:200'],
            'allocations.*.supplier_invoice_id' => ['required', 'integer', 'distinct'],
            'allocations.*.amount' => ['required', 'numeric', 'min:0'],
            'post' => ['nullable', 'boolean'],
        ]);

        $payment = DB::transaction(function () use ($data, $request) {
            $payment = $this->payments->create($data, $request->user());

            return ! empty($data['post']) ? $this->payments->post($payment, $request->user()) : $payment;
        });

        return response()->json(['data' => $payment], 201);
    }

    public function post(Request $request, SupplierPayment $payment): JsonResponse
    {
        $result = $this->payments->post($payment, $request->user());

        return response()->json(['message' => "{$result->number} posted.", 'data' => $result]);
    }

    public function cancel(Request $request, SupplierPayment $payment): JsonResponse
    {
        $result = $this->payments->cancel($payment, $request->user());

        return response()->json(['message' => "{$result->number} cancelled.", 'data' => $result]);
    }
}
