<?php

namespace App\Http\Controllers\Api\Erp\Finance;

use App\Http\Controllers\Controller;
use App\Models\Erp\Account;
use App\Services\Erp\Finance\Budgets;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class BudgetController extends Controller
{
    public function __construct(private readonly Budgets $budgets, private readonly TenantContext $tenant) {}

    public function show(int $year): JsonResponse
    {
        abort_unless($year >= 2000 && $year <= 2100, 404);

        return response()->json(['data' => [
            ...$this->budgets->show($year),
            'accounts' => Account::query()->whereIn('type', ['income', 'expense'])->where('is_active', true)->orderBy('code')->get(['id', 'code', 'name', 'type']),
        ]]);
    }

    public function update(Request $request, int $year): JsonResponse
    {
        abort_unless($year >= 2000 && $year <= 2100, 404);

        $data = $request->validate([
            'name' => ['nullable', 'string', 'max:120'],
            'notes' => ['nullable', 'string', 'max:500'],
            'lines' => ['present', 'array', 'max:500'],
            'lines.*.account_id' => ['required', 'integer', Rule::exists('accounts', 'id')->where('company_id', $this->tenant->id())],
            'lines.*.months' => ['required', 'array', 'size:12'],
            'lines.*.months.*' => ['nullable', 'numeric', 'min:0', 'max:999999999999'],
        ]);

        $budget = $this->budgets->save($year, $data['name'] ?? null, $data['lines'], $request->user(), $data['notes'] ?? null);

        return response()->json(['message' => "Budget for {$year} saved.", 'data' => [...$this->budgets->show($year), 'id' => $budget->id]]);
    }
}
