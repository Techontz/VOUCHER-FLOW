<?php

namespace App\Services\Erp\Finance;

use App\Models\Erp\Account;
use App\Models\Erp\Finance\AssetClass;
use App\Services\Erp\ChartOfAccounts;
use App\Support\TenantContext;

/**
 * The asset classes a company starts with, following the wear and tear
 * classes of Tanzania's Income Tax Act 2004 (Third Schedule): computers
 * 37.5%, heavy vehicles and plant 25%, furniture 12.5% on the reducing
 * balance, buildings 5% straight line. Every rate stays editable.
 */
class AssetClasses
{
    /** @var list<array{0: string, 1: string, 2: string, 3: int, 4: float, 5: string, 6: string}> code, name, method, life months, rate, asset key, depreciation key */
    public const DEFAULTS = [
        ['PLANT', 'Plant & machinery', 'reducing_balance', 120, 25.0, 'fa_plant', 'fa_plant_depreciation'],
        ['VEH', 'Motor vehicles', 'reducing_balance', 120, 25.0, 'fa_vehicles', 'fa_vehicles_depreciation'],
        ['COMP', 'Computers & IT equipment', 'reducing_balance', 96, 37.5, 'fa_computers', 'fa_computers_depreciation'],
        ['FURN', 'Furniture & fittings', 'reducing_balance', 180, 12.5, 'fa_furniture', 'fa_furniture_depreciation'],
        ['BLDG', 'Buildings', 'straight_line', 240, 5.0, 'fa_buildings', 'fa_buildings_depreciation'],
    ];

    public function __construct(private readonly TenantContext $tenant, private readonly ChartOfAccounts $chart) {}

    /** Adds the default classes a company is missing; returns how many were added. */
    public function ensureDefaults(): int
    {
        if (AssetClass::query()->exists() || ! ($company = $this->tenant->company())) {
            return 0;
        }

        $this->chart->seed($company);
        $ids = Account::query()->whereNotNull('system_key')->pluck('id', 'system_key');
        $added = 0;

        foreach (self::DEFAULTS as [$code, $name, $method, $life, $rate, $assetKey, $depreciationKey]) {
            if (! isset($ids[$assetKey], $ids[$depreciationKey], $ids['depreciation'])) {
                continue;
            }

            AssetClass::create([
                'company_id' => $company->id,
                'code' => $code, 'name' => $name, 'method' => $method,
                'useful_life_months' => $life, 'rate' => $rate,
                'asset_account_id' => $ids[$assetKey],
                'depreciation_account_id' => $ids[$depreciationKey],
                'expense_account_id' => $ids['depreciation'],
            ]);
            $added++;
        }

        return $added;
    }
}
