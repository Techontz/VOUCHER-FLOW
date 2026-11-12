<?php

namespace App\Services\Erp\Finance;

use App\Models\Erp\Finance\AssetClass;
use App\Models\Erp\Finance\AssetDepreciationLine;
use App\Models\Erp\Finance\AssetDepreciationRun;
use App\Models\Erp\Finance\FixedAsset;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Monthly depreciation.
 *
 * An asset's schedule is fixed by its cost, residual value, method, life and
 * rate: depreciation begins the month after acquisition and each month's
 * amount is worked in whole cents (straight line: equal months with the
 * rounding taken in the last; reducing balance: the annual rate on the
 * opening book value, a twelfth a month). A run for a month posts, for every
 * active asset, each scheduled month up to it that is not yet posted, so a
 * late-registered asset catches up and the posted total always equals the
 * schedule. The (asset, month) key refuses a month twice.
 */
class Depreciation
{
    public function __construct(
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    /**
     * The asset's full schedule, each month marked posted or not.
     *
     * @return list<array{period: string, opening: float, amount: float, closing: float, posted: bool}>
     */
    public function schedule(FixedAsset $asset): array
    {
        $posted = $asset->exists
            ? AssetDepreciationLine::query()->where('fixed_asset_id', $asset->id)->pluck('amount', 'period')->all()
            : [];
        $rows = [];
        foreach ($this->months($asset) as $row) {
            $isPosted = array_key_exists($row['period'], $posted);
            // A disposed asset's schedule ends with what was actually posted.
            if ($asset->status === FixedAsset::STATUS_DISPOSED && ! $isPosted) {
                continue;
            }
            $rows[] = [...$row, 'posted' => $isPosted];
        }

        return $rows;
    }

    /**
     * Months due for one asset up to and including a period, not yet posted.
     *
     * @return list<array{period: string, opening: float, amount: float, closing: float}>
     */
    public function dueFor(FixedAsset $asset, string $period): array
    {
        $posted = AssetDepreciationLine::query()->where('fixed_asset_id', $asset->id)->pluck('period')->flip()->all();

        return array_values(array_filter($this->months($asset), fn ($r) => $r['period'] <= $period && ! isset($posted[$r['period']])));
    }

    /** @return array<string, mixed> */
    public function preview(string $period): array
    {
        $this->assertPeriod($period);
        $lines = $this->due($period);

        return [
            'period' => $period,
            'run_date' => $this->runDate($period),
            'already_run' => AssetDepreciationRun::query()->where('period', $period)->exists(),
            'lines' => $lines->values()->all(),
            'total' => round($lines->sum('amount'), 2),
            'assets_count' => $lines->pluck('fixed_asset_id')->unique()->count(),
        ];
    }

    public function run(string $period, User $actor): AssetDepreciationRun
    {
        $this->assertPeriod($period);

        return DB::transaction(function () use ($period, $actor) {
            // One run at a time per company.
            DB::table('companies')->where('id', $this->tenant->id())->lockForUpdate()->first();

            if (AssetDepreciationRun::query()->where('period', $period)->exists()) {
                throw new RuntimeException("Depreciation for {$this->label($period)} has already been posted.");
            }

            $latest = AssetDepreciationRun::query()->max('period');
            if ($latest && $latest > $period) {
                throw new RuntimeException("Depreciation has already been run up to {$this->label($latest)}; an earlier month cannot be run after it.");
            }

            $runDate = $this->runDate($period);
            PeriodLock::assertOpen($runDate);

            $assets = FixedAsset::query()->where('status', FixedAsset::STATUS_ACTIVE)->lockForUpdate()->get();
            $lines = $this->due($period, $assets);

            if ($lines->isEmpty()) {
                throw new RuntimeException("No asset has depreciation due for {$this->label($period)}.");
            }

            $run = AssetDepreciationRun::create([
                'number' => $this->numbers->next('DPR'),
                'period' => $period,
                'run_date' => $runDate,
                'total' => round($lines->sum('amount'), 2),
                'assets_count' => $lines->pluck('fixed_asset_id')->unique()->count(),
                'created_by' => $actor->id,
            ]);

            foreach ($lines as $line) {
                $run->lines()->create([
                    'company_id' => $run->company_id,
                    'fixed_asset_id' => $line['fixed_asset_id'],
                    'period' => $line['period'],
                    'opening_value' => $line['opening'],
                    'amount' => $line['amount'],
                    'closing_value' => $line['closing'],
                ]);
            }

            foreach ($lines->groupBy('fixed_asset_id') as $assetId => $assetLines) {
                $asset = $assets->firstWhere('id', $assetId);
                $asset->update(['accumulated_depreciation' => round((float) $asset->accumulated_depreciation + $assetLines->sum('amount'), 2)]);
            }

            if (BusinessConfig::of($this->tenant->company())->postsToLedger()) {
                $journalLines = [];
                foreach ($lines->groupBy(fn ($l) => $l['expense_account_id'].':'.$l['depreciation_account_id']) as $group) {
                    $amount = round($group->sum('amount'), 2);
                    $journalLines[] = ['account_id' => $group->first()['expense_account_id'], 'debit' => $amount, 'description' => "Depreciation {$period}"];
                    $journalLines[] = ['account_id' => $group->first()['depreciation_account_id'], 'credit' => $amount, 'description' => "Depreciation {$period}"];
                }

                $entry = $this->journal->post($journalLines, "Depreciation {$this->label($period)} ({$run->number})", $runDate, $run, 'post', $actor);
                $run->update(['journal_entry_id' => $entry->id]);
            }

            $this->audit->log('assets.depreciation.posted', "Posted depreciation for {$this->label($period)}: ".number_format((float) $run->total, 2), $run, actor: $actor);

            return $run->fresh(['lines.asset:id,tag,name', 'journal:id,number']);
        });
    }

    /**
     * Every scheduled month for the asset, ignoring what is posted.
     *
     * @return list<array{period: string, opening: float, amount: float, closing: float}>
     */
    public function months(FixedAsset $asset): array
    {
        $cost = (int) round((float) $asset->cost * 100);
        $residual = (int) round((float) $asset->residual_value * 100);
        $life = max(1, (int) $asset->useful_life_months);
        $rate = (float) $asset->rate;
        $straight = $asset->method !== AssetClass::METHOD_REDUCING_BALANCE;
        $month = CarbonImmutable::parse($asset->acquisition_date)->startOfMonth()->addMonth();
        $value = $cost;
        $rows = [];

        for ($i = 1; $i <= $life; $i++) {
            if ($value <= $residual) {
                break;
            }

            $amount = $straight
                ? ($i === $life ? $value - $residual : (int) round(($cost - $residual) / $life))
                : (int) round($value * $rate / 100 / 12);
            $amount = min($amount, $value - $residual);

            if ($amount <= 0) {
                break;
            }

            $rows[] = [
                'period' => $month->format('Y-m'),
                'opening' => $value / 100,
                'amount' => $amount / 100,
                'closing' => ($value - $amount) / 100,
            ];
            $value -= $amount;
            $month = $month->addMonth();
        }

        return $rows;
    }

    /**
     * @param  Collection<int, FixedAsset>|null  $assets
     * @return Collection<int, array<string, mixed>>
     */
    private function due(string $period, ?Collection $assets = null): Collection
    {
        $assets ??= FixedAsset::query()->where('status', FixedAsset::STATUS_ACTIVE)->get();
        $assets->loadMissing('assetClass');

        return $assets->flatMap(fn (FixedAsset $asset) => array_map(fn ($row) => [
            ...$row,
            'fixed_asset_id' => $asset->id,
            'tag' => $asset->tag,
            'name' => $asset->name,
            'class' => $asset->assetClass?->name,
            'expense_account_id' => $asset->assetClass->expense_account_id,
            'depreciation_account_id' => $asset->assetClass->depreciation_account_id,
        ], $this->dueFor($asset, $period)))->values();
    }

    private function runDate(string $period): string
    {
        return CarbonImmutable::createFromFormat('Y-m', $period)->endOfMonth()->toDateString();
    }

    private function label(string $period): string
    {
        return CarbonImmutable::createFromFormat('Y-m', $period)->startOfMonth()->format('F Y');
    }

    private function assertPeriod(string $period): void
    {
        if (! preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $period)) {
            throw new RuntimeException('A period is a month written YYYY-MM.');
        }

        if ($period > now()->format('Y-m')) {
            throw new RuntimeException('Depreciation cannot be run for a month that has not started.');
        }
    }
}
