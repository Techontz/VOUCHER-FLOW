<?php

namespace App\Http\Controllers\Api\Erp;

use App\Http\Controllers\Controller;
use App\Models\Erp\JournalEntry;
use App\Services\Erp\ChartOfAccounts;
use App\Services\Erp\JournalPoster;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class JournalController extends Controller
{
    public function __construct(private readonly JournalPoster $poster, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(JournalEntry::query()
            ->with(['lines.account:id,code,name', 'creator:id,name'])
            ->when($request->query('source_type'), fn ($q, $v) => $q->where('source_type', $v))
            ->when($request->query('from'), fn ($q, $v) => $q->where('entry_date', '>=', $v))
            ->when($request->query('to'), fn ($q, $v) => $q->where('entry_date', '<=', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")->orWhere('memo', 'like', "%{$v}%")))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(JournalEntry $journalEntry): JsonResponse
    {
        return response()->json(['data' => $journalEntry->load('lines.account:id,code,name,type', 'creator:id,name', 'reversalOf:id,number')]);
    }

    /** A manual journal. Entries from documents are posted by those documents. */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'entry_date' => ['nullable', 'date'],
            'memo' => ['required', 'string', 'max:255'],
            'lines' => ['required', 'array', 'min:2', 'max:100'],
            'lines.*.account_id' => ['required', 'integer', Rule::exists('accounts', 'id')->where('company_id', $this->tenant->id())],
            'lines.*.debit' => ['nullable', 'numeric', 'min:0'],
            'lines.*.credit' => ['nullable', 'numeric', 'min:0'],
            'lines.*.description' => ['nullable', 'string', 'max:255'],
        ]);

        $entry = $this->poster->post($data['lines'], $data['memo'], $data['entry_date'] ?? null, actor: $request->user());

        return response()->json(['message' => "Journal {$entry->number} posted.", 'data' => $entry], 201);
    }

    public function reverse(Request $request, JournalEntry $journalEntry): JsonResponse
    {
        $reason = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:200']])['reason'];
        $reversal = $this->poster->reverse($journalEntry, $reason, $request->user());

        return response()->json(['message' => "Journal {$journalEntry->number} reversed by {$reversal->number}.", 'data' => $reversal]);
    }

    public function trialBalance(Request $request, ChartOfAccounts $chart): JsonResponse
    {
        $range = $request->validate(['from' => ['nullable', 'date'], 'to' => ['nullable', 'date']]);

        return response()->json(['data' => $chart->trialBalance($range['from'] ?? null, $range['to'] ?? null)]);
    }
}
