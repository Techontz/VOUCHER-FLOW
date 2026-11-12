<?php

namespace App\Services\Erp\Finance;

use App\Models\Erp\Finance\AssetClass;
use App\Models\Erp\Finance\AssetEvent;
use App\Models\Erp\Finance\BankAccount;
use App\Models\Erp\Finance\FixedAsset;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\JournalPoster;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * The asset register: registration (a draft), capitalisation (the
 * acquisition posts once: Dr the class's asset account / Cr payable, bank or
 * opening balance equity), transfers between places and custodians, and
 * disposal (posted once, with the gain or loss).
 */
class FixedAssets
{
    public const FUNDING = ['payable', 'bank', 'opening_equity'];

    public function __construct(
        private readonly JournalPoster $journal,
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
        private readonly BankAccounts $banks,
        private readonly Depreciation $depreciation,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function register(array $data, User $actor): FixedAsset
    {
        return DB::transaction(function () use ($data, $actor) {
            $class = AssetClass::query()->findOrFail($data['asset_class_id']);

            $asset = FixedAsset::create([
                ...$this->fields($data, $class),
                'tag' => filled($data['tag'] ?? null) ? $data['tag'] : $this->numbers->next('FA'),
                'status' => FixedAsset::STATUS_DRAFT,
                'created_by' => $actor->id,
            ]);

            $this->event($asset, 'registered', $asset->acquisition_date->toDateString(), $actor, [
                'to_location' => $asset->location, 'to_custodian_id' => $asset->custodian_user_id, 'amount' => $asset->cost,
            ]);
            $this->audit->log('assets.registered', "Registered asset {$asset->tag} {$asset->name}", $asset, actor: $actor);

            return $asset;
        });
    }

    /** @param  array<string, mixed>  $data */
    public function update(FixedAsset $asset, array $data, User $actor): FixedAsset
    {
        return DB::transaction(function () use ($asset, $data, $actor) {
            $locked = $this->lock($asset);

            if ($locked->status === FixedAsset::STATUS_DRAFT) {
                $class = AssetClass::query()->findOrFail($data['asset_class_id'] ?? $locked->asset_class_id);
                $locked->update([...$this->fields([...$locked->toArray(), ...$data, 'acquisition_date' => $data['acquisition_date'] ?? $locked->acquisition_date->toDateString()], $class), 'tag' => $data['tag'] ?? $locked->tag]);
            } else {
                // Cost, dates and the depreciation basis are fixed once the
                // asset is on the books; only its description may change.
                $locked->update(collect($data)->only(['name', 'description', 'serial_number'])->all());
            }

            $this->audit->log('assets.updated', "Updated asset {$locked->tag}", $locked, actor: $actor);

            return $locked;
        });
    }

    public function capitalise(FixedAsset $asset, string $funding, ?int $bankAccountId, User $actor): FixedAsset
    {
        return DB::transaction(function () use ($asset, $funding, $bankAccountId, $actor) {
            $locked = $this->lock($asset);

            if ($locked->status !== FixedAsset::STATUS_DRAFT) {
                throw new RuntimeException("{$locked->tag} is already capitalised.");
            }

            if (! in_array($funding, self::FUNDING, true)) {
                throw new RuntimeException('Say how the asset was paid for: on credit (payable), from a bank account, or brought in from before (opening balance).');
            }

            if ($funding === 'payable' && ! $locked->supplier_id) {
                throw new RuntimeException('An asset bought on credit needs its supplier.');
            }

            $bank = $funding === 'bank' ? BankAccount::query()->find($bankAccountId) : null;
            if ($funding === 'bank' && ! $bank) {
                throw new RuntimeException('Choose the bank account the asset was paid from.');
            }

            $date = $locked->acquisition_date->toDateString();
            $entryId = null;

            if ($this->postsToLedger()) {
                PeriodLock::assertOpen($date);
                $cost = round((float) $locked->cost, 2);

                if ($bank) {
                    $this->banks->assertCanPay($bank, $cost, $date);
                }

                $credit = match ($funding) {
                    'bank' => ['account_id' => $bank->account_id],
                    'payable' => ['account' => 'payable'],
                    default => ['account' => 'opening_equity'],
                };

                $entry = $this->journal->post([
                    ['account_id' => $locked->assetClass->asset_account_id, 'debit' => $cost, 'description' => "{$locked->tag} {$locked->name}"],
                    [...$credit, 'credit' => $cost, 'description' => "{$locked->tag} {$locked->name}"],
                ], "Acquisition of {$locked->tag} {$locked->name}", $date, $locked, 'acquisition', $actor);
                $entryId = $entry->id;
            }

            $locked->update([
                'status' => FixedAsset::STATUS_ACTIVE,
                'funding' => $funding,
                'funding_bank_account_id' => $bank?->id,
                'acquisition_entry_id' => $entryId,
                'capitalised_at' => now(),
            ]);

            $this->event($locked, 'capitalised', $date, $actor, ['amount' => $locked->cost, 'journal_entry_id' => $entryId]);
            $this->audit->log('assets.capitalised', "Capitalised {$locked->tag} at ".number_format((float) $locked->cost, 2), $locked, actor: $actor);

            return $locked;
        });
    }

    /** @param  array<string, mixed>  $data */
    public function transfer(FixedAsset $asset, array $data, User $actor): FixedAsset
    {
        return DB::transaction(function () use ($asset, $data, $actor) {
            $locked = $this->lock($asset);

            if ($locked->status === FixedAsset::STATUS_DISPOSED) {
                throw new RuntimeException("{$locked->tag} has been disposed of.");
            }

            $toLocation = $data['location'] ?? $locked->location;
            $toCustodian = array_key_exists('custodian_user_id', $data) ? $data['custodian_user_id'] : $locked->custodian_user_id;

            if ($toLocation === $locked->location && (int) $toCustodian === (int) $locked->custodian_user_id) {
                throw new RuntimeException('Choose a new location or custodian.');
            }

            $this->event($locked, 'transferred', $data['date'] ?? now()->toDateString(), $actor, [
                'from_location' => $locked->location, 'to_location' => $toLocation,
                'from_custodian_id' => $locked->custodian_user_id, 'to_custodian_id' => $toCustodian,
                'notes' => $data['notes'] ?? null,
            ]);

            $locked->update(['location' => $toLocation, 'custodian_user_id' => $toCustodian]);
            $this->audit->log('assets.transferred', "Moved {$locked->tag} to {$toLocation}", $locked, actor: $actor);

            return $locked;
        });
    }

    /** @param  array<string, mixed>  $data */
    public function dispose(FixedAsset $asset, array $data, User $actor): FixedAsset
    {
        return DB::transaction(function () use ($asset, $data, $actor) {
            $locked = $this->lock($asset);

            if ($locked->status !== FixedAsset::STATUS_ACTIVE) {
                throw new RuntimeException($locked->status === FixedAsset::STATUS_DISPOSED
                    ? "{$locked->tag} has already been disposed of."
                    : "{$locked->tag} is not capitalised yet; delete the draft instead.");
            }

            $date = CarbonImmutable::parse($data['disposal_date']);
            $period = $date->format('Y-m');

            if ($date->lt($locked->acquisition_date)) {
                throw new RuntimeException('An asset cannot be disposed of before it was acquired.');
            }

            if ($locked->depreciationLines()->where('period', '>', $period)->exists()) {
                throw new RuntimeException("Depreciation is already posted for {$locked->tag} after {$date->format('F Y')}; dispose of it no earlier than the last month depreciated.");
            }

            $due = $this->depreciation->dueFor($locked, $date->startOfMonth()->subMonth()->format('Y-m'));
            if ($due) {
                throw new RuntimeException("Depreciation for {$locked->tag} is due for ".CarbonImmutable::createFromFormat('Y-m', end($due)['period'])->format('F Y').' and not posted. Run depreciation for that month before disposing.');
            }

            $proceeds = round((float) ($data['proceeds'] ?? 0), 2);
            $bank = $proceeds > 0 ? BankAccount::query()->find($data['bank_account_id'] ?? null) : null;

            if ($proceeds > 0 && ! $bank) {
                throw new RuntimeException('Choose the bank account the sale proceeds went into.');
            }

            $cost = round((float) $locked->cost, 2);
            $accumulated = round((float) $locked->accumulated_depreciation, 2);
            $gain = round($proceeds - ($cost - $accumulated), 2);
            $entryId = null;

            if ($this->postsToLedger()) {
                PeriodLock::assertOpen($date->toDateString());
                $class = $locked->assetClass;
                $text = "Disposal of {$locked->tag}";
                $lines = [['account_id' => $class->asset_account_id, 'credit' => $cost, 'description' => $text]];

                if ($accumulated > 0) {
                    $lines[] = ['account_id' => $class->depreciation_account_id, 'debit' => $accumulated, 'description' => $text];
                }
                if ($proceeds > 0) {
                    $lines[] = ['account_id' => $bank->account_id, 'debit' => $proceeds, 'description' => $text];
                }
                if ($gain > 0) {
                    $lines[] = ['account' => 'other_income', 'credit' => $gain, 'description' => "Gain on {$text}"];
                } elseif ($gain < 0) {
                    $lines[] = ['account' => 'disposal_loss', 'debit' => -$gain, 'description' => "Loss on {$text}"];
                }

                $entry = $this->journal->post($lines, "{$text} {$locked->name}", $date->toDateString(), $locked, 'disposal', $actor);
                $entryId = $entry->id;
            }

            $locked->update([
                'status' => FixedAsset::STATUS_DISPOSED,
                'disposal_date' => $date->toDateString(),
                'disposal_proceeds' => $proceeds,
                'disposal_gain_loss' => $gain,
                'disposal_bank_account_id' => $bank?->id,
                'disposal_entry_id' => $entryId,
                'disposal_reason' => $data['reason'] ?? null,
            ]);

            $this->event($locked, 'disposed', $date->toDateString(), $actor, [
                'amount' => $proceeds, 'notes' => $data['reason'] ?? null, 'journal_entry_id' => $entryId, 'from_location' => $locked->location,
            ]);
            $this->audit->log('assets.disposed', sprintf('Disposed of %s for %s (%s %s)', $locked->tag, number_format($proceeds, 2), $gain >= 0 ? 'gain' : 'loss', number_format(abs($gain), 2)), $locked, actor: $actor);

            return $locked;
        });
    }

    public function delete(FixedAsset $asset, User $actor): void
    {
        DB::transaction(function () use ($asset, $actor) {
            $locked = $this->lock($asset);

            if ($locked->status !== FixedAsset::STATUS_DRAFT) {
                throw new RuntimeException("{$locked->tag} is on the books; dispose of it instead of deleting it.");
            }

            $locked->events()->delete();
            $locked->delete();
            $this->audit->log('assets.deleted', "Deleted draft asset {$locked->tag}", $locked, actor: $actor);
        });
    }

    /** @return array<string, mixed> */
    private function fields(array $data, AssetClass $class): array
    {
        $cost = round((float) $data['cost'], 2);
        $residual = round((float) ($data['residual_value'] ?? 0), 2);

        if ($cost <= 0) {
            throw new RuntimeException('Enter the cost of the asset.');
        }

        if ($residual < 0 || $residual >= $cost) {
            throw new RuntimeException('The residual value must be less than the cost.');
        }

        $method = $data['method'] ?? $class->method;
        $rate = (float) ($data['rate'] ?? $class->rate);

        if ($method === AssetClass::METHOD_REDUCING_BALANCE && $rate <= 0) {
            throw new RuntimeException('Reducing balance needs an annual rate.');
        }

        return [
            'name' => $data['name'],
            'description' => $data['description'] ?? null,
            'asset_class_id' => $class->id,
            'serial_number' => $data['serial_number'] ?? null,
            'location' => $data['location'] ?? null,
            'custodian_user_id' => $data['custodian_user_id'] ?? null,
            'supplier_id' => $data['supplier_id'] ?? null,
            'acquisition_date' => $data['acquisition_date'],
            'cost' => $cost,
            'residual_value' => $residual,
            'method' => $method,
            'useful_life_months' => (int) ($data['useful_life_months'] ?? $class->useful_life_months),
            'rate' => $rate,
        ];
    }

    /** @param  array<string, mixed>  $extra */
    private function event(FixedAsset $asset, string $type, string $date, User $actor, array $extra = []): AssetEvent
    {
        return AssetEvent::create([
            'company_id' => $asset->company_id,
            'fixed_asset_id' => $asset->id,
            'type' => $type,
            'event_date' => $date,
            'user_id' => $actor->id,
            ...$extra,
        ]);
    }

    private function postsToLedger(): bool
    {
        return BusinessConfig::of($this->tenant->company())->postsToLedger();
    }

    private function lock(FixedAsset $asset): FixedAsset
    {
        return FixedAsset::query()->whereKey($asset->id)->lockForUpdate()->firstOrFail();
    }
}
