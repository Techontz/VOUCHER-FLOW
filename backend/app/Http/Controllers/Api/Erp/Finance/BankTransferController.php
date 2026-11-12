<?php

namespace App\Http\Controllers\Api\Erp\Finance;

use App\Http\Controllers\Controller;
use App\Models\Erp\Finance\BankTransfer;
use App\Services\Erp\Finance\BankTransfers;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class BankTransferController extends Controller
{
    public function __construct(private readonly BankTransfers $transfers, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(BankTransfer::query()
            ->with(['from:id,name', 'to:id,name', 'creator:id,name'])
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('bank_account_id'), fn ($q, $v) => $q->where(fn ($w) => $w->where('from_bank_account_id', $v)->orWhere('to_bank_account_id', $v)))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")->orWhere('reference', 'like', "%{$v}%")->orWhere('memo', 'like', "%{$v}%")))
            ->latest('transfer_date')->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(BankTransfer $bankTransfer): JsonResponse
    {
        return response()->json(['data' => $bankTransfer->load('from', 'to', 'creator:id,name', 'poster:id,name', 'reverser:id,name', 'journal.lines.account:id,code,name')]);
    }

    public function store(Request $request): JsonResponse
    {
        return response()->json(['data' => $this->transfers->create($this->rules($request), $request->user())], 201);
    }

    public function update(Request $request, BankTransfer $bankTransfer): JsonResponse
    {
        return response()->json(['data' => $this->transfers->update($bankTransfer, $this->rules($request), $request->user())]);
    }

    public function post(Request $request, BankTransfer $bankTransfer): JsonResponse
    {
        $transfer = $this->transfers->post($bankTransfer, $request->user());

        return response()->json(['message' => "{$transfer->number} posted.", 'data' => $transfer]);
    }

    public function reverse(Request $request, BankTransfer $bankTransfer): JsonResponse
    {
        $reason = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:255']])['reason'];
        $transfer = $this->transfers->reverse($bankTransfer, $reason, $request->user());

        return response()->json(['message' => "{$transfer->number} reversed.", 'data' => $transfer]);
    }

    public function cancel(Request $request, BankTransfer $bankTransfer): JsonResponse
    {
        return response()->json(['message' => 'Draft cancelled.', 'data' => $this->transfers->cancel($bankTransfer, $request->user())]);
    }

    /** @return array<string, mixed> */
    private function rules(Request $request): array
    {
        $bank = Rule::exists('bank_accounts', 'id')->where('company_id', $this->tenant->id());

        return $request->validate([
            'transfer_date' => ['required', 'date', 'before_or_equal:today'],
            'from_bank_account_id' => ['required', 'integer', $bank],
            'to_bank_account_id' => ['required', 'integer', $bank, 'different:from_bank_account_id'],
            'amount' => ['required', 'numeric', 'min:0.01', 'max:999999999999'],
            'charges' => ['nullable', 'numeric', 'min:0', 'max:999999999'],
            'reference' => ['nullable', 'string', 'max:80'],
            'memo' => ['nullable', 'string', 'max:255'],
        ]);
    }
}
