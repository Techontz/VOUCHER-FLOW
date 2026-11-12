<?php

namespace App\Http\Controllers\Api\Erp\Finance;

use App\Http\Controllers\Controller;
use App\Models\Erp\Finance\YearEndClosing;
use App\Services\Erp\Finance\FiscalYear;
use App\Services\Erp\Finance\PeriodClosing;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PeriodController extends Controller
{
    public function __construct(private readonly PeriodClosing $periods) {}

    public function index(Request $request): JsonResponse
    {
        $year = (int) ($request->validate(['year' => ['nullable', 'integer', 'between:2000,2100']])['year'] ?? FiscalYear::of(now()->toImmutable()));

        return response()->json(['data' => [
            ...$this->periods->year($year),
            'closed_years' => YearEndClosing::query()->orderByDesc('fiscal_year')->get(['id', 'fiscal_year', 'net_profit', 'journal_entry_id', 'created_at']),
        ]]);
    }

    public function close(Request $request, string $period): JsonResponse
    {
        $row = $this->periods->close($period, $request->user());

        return response()->json(['message' => "{$row->starts_on->format('F Y')} closed.", 'data' => $row]);
    }

    public function reopen(Request $request, string $period): JsonResponse
    {
        $reason = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:255']])['reason'];
        $row = $this->periods->reopen($period, $reason, $request->user());

        return response()->json(['message' => "{$row->starts_on->format('F Y')} reopened.", 'data' => $row]);
    }

    public function closeYear(Request $request, int $year): JsonResponse
    {
        $closing = $this->periods->closeYear($year, $request->user());

        return response()->json(['message' => "Fiscal year {$year} closed.", 'data' => $closing]);
    }
}
