<?php

namespace App\Http\Controllers\Api\Erp\Finance;

use App\Http\Controllers\Controller;
use App\Models\Erp\Finance\BankAccount;
use App\Models\Erp\Finance\BankReconciliation;
use App\Services\Erp\Finance\BankAccounts;
use App\Services\Erp\Finance\Ledger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class BankAccountController extends Controller
{
    public function __construct(private readonly BankAccounts $banks, private readonly Ledger $ledger) {}

    public function index(Request $request): JsonResponse
    {
        $rows = BankAccount::query()->with('account:id,code,name')
            ->when($request->boolean('active'), fn ($q) => $q->where('is_active', true))
            ->orderByDesc('is_active')->orderBy('name')->get();
        $balances = $this->ledger->balances($rows->pluck('account_id')->all());

        return response()->json(['data' => $rows->each(fn (BankAccount $b) => $b->setAttribute('balance', $balances[$b->account_id] ?? 0.0))]);
    }

    public function show(Request $request, BankAccount $bankAccount): JsonResponse
    {
        $range = $request->validate(['from' => ['nullable', 'date'], 'to' => ['nullable', 'date']]);
        $from = $range['from'] ?? now()->subMonths(3)->startOfMonth()->toDateString();
        $to = $range['to'] ?? now()->toDateString();
        $accountId = $bankAccount->account_id;

        $opening = $this->ledger->balance($accountId, now()->parse($from)->subDay()->toDateString());
        $running = $opening;

        $lines = $this->ledger->lines($from, $to)->where('journal_lines.account_id', $accountId)
            ->orderBy('journal_entries.entry_date')->orderBy('journal_lines.id')
            ->select('journal_lines.id', 'journal_lines.debit', 'journal_lines.credit', 'journal_lines.description',
                'journal_entries.id as journal_entry_id', 'journal_entries.entry_date', 'journal_entries.number',
                'journal_entries.memo', 'journal_entries.source_type', 'journal_entries.source_id')
            ->selectRaw('EXISTS(SELECT 1 FROM bank_statement_lines WHERE bank_statement_lines.journal_line_id = journal_lines.id) AS reconciled')
            ->get()
            ->map(function ($l) use (&$running) {
                $running = round($running + (float) $l->debit - (float) $l->credit, 2);

                return [...(array) $l, 'reconciled' => (bool) $l->reconciled, 'balance' => $running];
            });

        return response()->json(['data' => [
            ...$bankAccount->load('account:id,code,name', 'openingEntry:id,number')->toArray(),
            'balance' => $this->ledger->balance($accountId),
            'statement' => ['from' => $from, 'to' => $to, 'opening' => $opening, 'closing' => $running, 'lines' => $lines],
            'reconciliations' => BankReconciliation::query()->where('bank_account_id', $bankAccount->id)->latest('statement_date')->limit(12)->get(),
        ]]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            ...$this->rules(),
            'code' => ['nullable', 'integer', 'between:1201,1299'],
            'opening_balance' => ['nullable', 'numeric', 'between:-999999999999,999999999999'],
            'opening_date' => ['nullable', 'date', 'before_or_equal:today'],
        ]);

        return response()->json(['data' => $this->banks->create($data, $request->user())], 201);
    }

    public function update(Request $request, BankAccount $bankAccount): JsonResponse
    {
        $data = $request->validate([...array_map(fn ($r) => ['sometimes', ...$r], $this->rules()), 'is_active' => ['sometimes', 'boolean']]);

        return response()->json(['data' => $this->banks->update($bankAccount, $data, $request->user())]);
    }

    /** @return array<string, list<mixed>> */
    private function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:120'],
            'type' => ['required', Rule::in(BankAccount::TYPES)],
            'bank_name' => ['nullable', 'string', 'max:120'],
            'branch' => ['nullable', 'string', 'max:120'],
            'account_name' => ['nullable', 'string', 'max:160'],
            'account_number' => ['nullable', 'string', 'max:60'],
            'currency' => ['nullable', 'string', 'size:3'],
            'notes' => ['nullable', 'string', 'max:500'],
        ];
    }
}
