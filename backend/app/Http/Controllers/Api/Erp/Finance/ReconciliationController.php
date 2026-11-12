<?php

namespace App\Http\Controllers\Api\Erp\Finance;

use App\Http\Controllers\Controller;
use App\Models\Erp\Finance\BankAccount;
use App\Models\Erp\Finance\BankReconciliation;
use App\Models\Erp\Finance\BankStatementLine;
use App\Services\Erp\Finance\Reconciliations;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class ReconciliationController extends Controller
{
    public function __construct(private readonly Reconciliations $reconciliations, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(BankReconciliation::query()
            ->with(['bankAccount:id,name', 'creator:id,name', 'completer:id,name'])
            ->withCount('lines')
            ->when($request->query('bank_account_id'), fn ($q, $v) => $q->where('bank_account_id', $v))
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->latest('statement_date')->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(BankReconciliation $bankReconciliation): JsonResponse
    {
        $rec = $bankReconciliation->load('bankAccount.account:id,code,name', 'creator:id,name', 'completer:id,name');
        $lines = $rec->lines()->with('journalLine.entry:id,number,entry_date,memo')->orderBy('line_date')->orderBy('id')->get();
        $outstanding = $this->reconciliations->outstanding($rec);

        return response()->json(['data' => [
            ...$rec->toArray(),
            'lines' => $lines->map(fn (BankStatementLine $l) => [
                ...$l->toArray(),
                'suggestions' => $rec->isOpen() && ! $l->journal_line_id ? $this->reconciliations->suggestions($l) : [],
            ]),
            'outstanding' => $outstanding->map(fn ($o) => [...(array) $o, 'amount' => round((float) $o->debit - (float) $o->credit, 2)]),
            'summary' => $this->reconciliations->summary($rec),
        ]]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'bank_account_id' => ['required', 'integer', Rule::exists('bank_accounts', 'id')->where('company_id', $this->tenant->id())],
            ...$this->balanceRules(),
        ]);
        $bank = BankAccount::query()->findOrFail($data['bank_account_id']);

        return response()->json(['data' => $this->reconciliations->start($bank, $data, $request->user())], 201);
    }

    public function update(Request $request, BankReconciliation $bankReconciliation): JsonResponse
    {
        $data = $request->validate($this->balanceRules());

        return response()->json(['data' => $this->reconciliations->update($bankReconciliation, $data, $request->user())]);
    }

    public function destroy(Request $request, BankReconciliation $bankReconciliation): JsonResponse
    {
        $this->reconciliations->delete($bankReconciliation, $request->user());

        return response()->json(['message' => 'Reconciliation deleted.']);
    }

    public function addLines(Request $request, BankReconciliation $bankReconciliation): JsonResponse
    {
        $data = $request->validate([
            'lines' => ['required', 'array', 'min:1', 'max:1000'],
            'lines.*.line_date' => ['required', 'date'],
            'lines.*.description' => ['required', 'string', 'max:255'],
            'lines.*.reference' => ['nullable', 'string', 'max:80'],
            'lines.*.amount' => ['required', 'numeric', 'not_in:0', 'between:-999999999999,999999999999'],
        ]);

        $lines = $this->reconciliations->addLines($bankReconciliation, $data['lines'], $request->user());

        return response()->json(['message' => "{$lines->count()} line(s) added.", 'data' => $lines], 201);
    }

    /** A statement CSV, as a file upload or pasted text. */
    public function import(Request $request, BankReconciliation $bankReconciliation): JsonResponse
    {
        $request->validate([
            'file' => ['required_without:csv', 'file', 'mimes:csv,txt', 'max:2048'],
            'csv' => ['required_without:file', 'string', 'max:1000000'],
        ]);

        $contents = $request->hasFile('file') ? (string) file_get_contents($request->file('file')->getRealPath()) : (string) $request->input('csv');
        $lines = $this->reconciliations->addLines($bankReconciliation, $this->reconciliations->parseCsv($contents), $request->user());
        $matched = $request->boolean('auto_match', true) ? $this->reconciliations->autoMatch($bankReconciliation, $request->user()) : 0;

        return response()->json(['message' => "Imported {$lines->count()} line(s); matched {$matched}.", 'imported' => $lines->count(), 'matched' => $matched], 201);
    }

    public function deleteLine(Request $request, BankReconciliation $bankReconciliation, int $line): JsonResponse
    {
        $this->reconciliations->deleteLine($this->line($bankReconciliation, $line), $request->user());

        return response()->json(['message' => 'Line deleted.']);
    }

    public function match(Request $request, BankReconciliation $bankReconciliation, int $line): JsonResponse
    {
        $id = $request->validate(['journal_line_id' => ['required', 'integer']])['journal_line_id'];

        return response()->json(['message' => 'Matched.', 'data' => $this->reconciliations->match($this->line($bankReconciliation, $line), $id, $request->user())]);
    }

    public function unmatch(Request $request, BankReconciliation $bankReconciliation, int $line): JsonResponse
    {
        return response()->json(['message' => 'Unmatched.', 'data' => $this->reconciliations->unmatch($this->line($bankReconciliation, $line), $request->user())]);
    }

    public function autoMatch(Request $request, BankReconciliation $bankReconciliation): JsonResponse
    {
        $matched = $this->reconciliations->autoMatch($bankReconciliation, $request->user());

        return response()->json(['message' => "Matched {$matched} line(s).", 'matched' => $matched]);
    }

    /** Books a bank-only item (charges, interest) through the cashbook and matches it. */
    public function createEntry(Request $request, BankReconciliation $bankReconciliation, int $line): JsonResponse
    {
        abort_unless($request->user()->hasPermission('finance.cashbook'), 403, 'Booking a statement line needs the permission to record receipts and payments.');
        $accountId = $request->validate(['account_id' => ['required', 'integer', Rule::exists('accounts', 'id')->where('company_id', $this->tenant->id())]])['account_id'];

        return response()->json(['message' => 'Entry posted and matched.', 'data' => $this->reconciliations->createEntry($this->line($bankReconciliation, $line), $accountId, $request->user())]);
    }

    public function complete(Request $request, BankReconciliation $bankReconciliation): JsonResponse
    {
        $rec = $this->reconciliations->complete($bankReconciliation, $request->user());

        return response()->json(['message' => "{$rec->number} completed.", 'data' => $rec]);
    }

    private function line(BankReconciliation $reconciliation, int $id): BankStatementLine
    {
        return $reconciliation->lines()->whereKey($id)->firstOrFail();
    }

    /** @return array<string, list<mixed>> */
    private function balanceRules(): array
    {
        return [
            'statement_date' => ['required', 'date', 'before_or_equal:today'],
            'statement_opening_balance' => ['nullable', 'numeric', 'between:-999999999999,999999999999'],
            'statement_closing_balance' => ['required', 'numeric', 'between:-999999999999,999999999999'],
            'notes' => ['nullable', 'string', 'max:500'],
        ];
    }
}
