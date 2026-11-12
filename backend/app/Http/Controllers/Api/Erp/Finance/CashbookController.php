<?php

namespace App\Http\Controllers\Api\Erp\Finance;

use App\Http\Controllers\Controller;
use App\Models\Erp\Account;
use App\Models\Erp\Finance\CashbookEntry;
use App\Services\Erp\Finance\Cashbook;
use App\Services\Erp\Finance\Ledger;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class CashbookController extends Controller
{
    public function __construct(private readonly Cashbook $cashbook, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        $query = CashbookEntry::query()
            ->with(['bankAccount:id,name', 'account:id,code,name', 'creator:id,name'])
            ->when($request->query('type'), fn ($q, $v) => $q->where('type', $v))
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('bank_account_id'), fn ($q, $v) => $q->where('bank_account_id', $v))
            ->when($request->query('account_id'), fn ($q, $v) => $q->where('account_id', $v))
            ->when($request->query('from'), fn ($q, $v) => $q->where('entry_date', '>=', $v))
            ->when($request->query('to'), fn ($q, $v) => $q->where('entry_date', '<=', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")
                ->orWhere('description', 'like', "%{$v}%")->orWhere('counterparty', 'like', "%{$v}%")->orWhere('reference', 'like', "%{$v}%")));

        $totals = (clone $query)->where('status', CashbookEntry::STATUS_POSTED)->reorder()
            ->selectRaw("COALESCE(SUM(CASE WHEN type = 'receipt' THEN amount END), 0) AS receipts, COALESCE(SUM(CASE WHEN type = 'payment' THEN amount END), 0) AS payments")
            ->first();

        return response()->json([
            ...$query->latest('entry_date')->latest('id')->paginate(min((int) $request->query('per_page', 30), 100))->toArray(),
            'totals' => ['receipts' => round((float) $totals->receipts, 2), 'payments' => round((float) $totals->payments, 2)],
        ]);
    }

    public function show(CashbookEntry $cashbookEntry): JsonResponse
    {
        return response()->json(['data' => $cashbookEntry->load('bankAccount', 'account:id,code,name,type', 'creator:id,name', 'poster:id,name', 'reverser:id,name', 'journal.lines.account:id,code,name')]);
    }

    /** Accounts a receipt or payment may be booked against: active, and not cash or bank. */
    public function accounts(): JsonResponse
    {
        return response()->json(['data' => Account::query()->where('is_active', true)->orderBy('code')->get(['id', 'code', 'name', 'type', 'system_key'])
            ->reject(fn (Account $a) => Ledger::isCashAccount($a))->values()]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->rules($request, true);

        return response()->json(['data' => $this->cashbook->create($data, $request->user())], 201);
    }

    public function update(Request $request, CashbookEntry $cashbookEntry): JsonResponse
    {
        return response()->json(['data' => $this->cashbook->update($cashbookEntry, $this->rules($request), $request->user())]);
    }

    public function post(Request $request, CashbookEntry $cashbookEntry): JsonResponse
    {
        $entry = $this->cashbook->post($cashbookEntry, $request->user());

        return response()->json(['message' => "{$entry->number} posted.", 'data' => $entry]);
    }

    public function reverse(Request $request, CashbookEntry $cashbookEntry): JsonResponse
    {
        $reason = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:255']])['reason'];
        $entry = $this->cashbook->reverse($cashbookEntry, $reason, $request->user());

        return response()->json(['message' => "{$entry->number} reversed.", 'data' => $entry]);
    }

    public function cancel(Request $request, CashbookEntry $cashbookEntry): JsonResponse
    {
        return response()->json(['message' => 'Draft cancelled.', 'data' => $this->cashbook->cancel($cashbookEntry, $request->user())]);
    }

    /** @return array<string, mixed> */
    private function rules(Request $request, bool $creating = false): array
    {
        $company = $this->tenant->id();

        return $request->validate([
            'type' => [$creating ? 'required' : 'prohibited', Rule::in(CashbookEntry::TYPES)],
            'entry_date' => ['required', 'date', 'before_or_equal:today'],
            'bank_account_id' => ['required', 'integer', Rule::exists('bank_accounts', 'id')->where('company_id', $company)],
            'account_id' => ['required', 'integer', Rule::exists('accounts', 'id')->where('company_id', $company)],
            'amount' => ['required', 'numeric', 'min:0.01', 'max:999999999999'],
            'counterparty' => ['nullable', 'string', 'max:160'],
            'reference' => ['nullable', 'string', 'max:80'],
            'description' => ['required', 'string', 'max:255'],
        ]);
    }
}
