<?php

namespace App\Services\Erp\Finance;

use App\Models\Erp\Account;
use App\Models\Erp\Finance\Budget;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/** A year's budget, one amount per income or expense account per month. */
class Budgets
{
    public function __construct(private readonly AuditLogger $audit) {}

    /**
     * Replaces the year's budget lines with the ones given.
     *
     * @param  list<array{account_id: int, months: list<float|int|string|null>}>  $lines
     */
    public function save(int $year, ?string $name, array $lines, User $actor, ?string $notes = null): Budget
    {
        $accounts = Account::query()->whereIn('id', array_column($lines, 'account_id'))->get()->keyBy('id');

        foreach ($lines as $line) {
            $account = $accounts[$line['account_id']] ?? throw new RuntimeException('One of the accounts is not in this company\'s chart.');
            if (! in_array($account->type, ['income', 'expense'], true)) {
                throw new RuntimeException("{$account->code} {$account->name} is not an income or expense account; budgets are set for those only.");
            }
            if (count($line['months']) !== 12) {
                throw new RuntimeException("{$account->code} {$account->name}: enter twelve monthly amounts.");
            }
        }

        if (count(array_unique(array_column($lines, 'account_id'))) !== count($lines)) {
            throw new RuntimeException('Each account may appear once in a budget.');
        }

        return DB::transaction(function () use ($year, $name, $lines, $actor, $notes) {
            $budget = Budget::query()->where('fiscal_year', $year)->lockForUpdate()->first()
                ?? Budget::create(['fiscal_year' => $year, 'name' => $name ?: "Budget {$year}", 'created_by' => $actor->id]);

            $budget->update(['name' => $name ?: $budget->name, 'notes' => $notes, 'updated_by' => $actor->id]);
            $budget->lines()->delete();

            foreach ($lines as $line) {
                foreach (array_values($line['months']) as $i => $amount) {
                    if ((float) $amount != 0.0) {
                        $budget->lines()->create(['account_id' => $line['account_id'], 'month' => $i + 1, 'amount' => round((float) $amount, 2)]);
                    }
                }
            }

            $this->audit->log('finance.budget.saved', "Saved budget for {$year} (".count($lines).' accounts)', $budget, actor: $actor);

            return $budget->load('lines');
        });
    }

    /** @return array<string, mixed> */
    public function show(int $year): array
    {
        $budget = Budget::query()->with('lines')->where('fiscal_year', $year)->first();
        $byAccount = collect($budget?->lines ?? [])->groupBy('account_id');

        return [
            'fiscal_year' => $year,
            'months' => FiscalYear::months($year),
            'budget' => $budget?->only(['id', 'name', 'notes', 'updated_at']),
            'lines' => $byAccount->map(function ($lines, $accountId) {
                $months = array_fill(0, 12, 0.0);
                foreach ($lines as $l) {
                    $months[$l->month - 1] = (float) $l->amount;
                }

                return ['account_id' => (int) $accountId, 'months' => $months, 'total' => round(array_sum($months), 2)];
            })->values()->all(),
        ];
    }
}
