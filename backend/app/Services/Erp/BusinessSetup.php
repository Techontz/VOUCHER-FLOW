<?php

namespace App\Services\Erp;

use App\Models\Company;
use App\Models\Erp\ProductCategory;
use App\Models\Erp\Unit;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Services\AuditLogger;
use App\Support\Erp\BusinessConfig;
use App\Support\Erp\BusinessTemplates;
use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Runs the setup wizard's final step: records the business type, modules and
 * settings, and seeds what the template brings, units, categories, a main
 * warehouse and the standard chart of accounts.
 *
 * Safe to run again. Anything the company already has (by code or name) is
 * left exactly as the company edited it; only what is missing is added.
 */
class BusinessSetup
{
    public function __construct(
        private readonly ChartOfAccounts $chart,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    /**
     * @param  list<string>|null  $modules  null takes the template's recommendation
     * @param  array<string, mixed>  $settings
     * @return array{units: int, categories: int, warehouses: int, accounts: int}
     */
    public function apply(Company $company, string $type, ?array $modules, array $settings, User $actor): array
    {
        $template = BusinessTemplates::get($type) ?? throw new RuntimeException("Unknown business type '{$type}'.");

        $config = BusinessConfig::of($company);
        $chosen = $modules !== null;
        $modules = array_values(array_unique(['vouchflow', ...($modules ?? $template['modules'])]));
        $unknown = array_diff($modules, array_keys(BusinessTemplates::modules()));

        if ($unknown) {
            throw new RuntimeException('Unknown module: '.implode(', ', $unknown).'.');
        }

        // Apps picked by hand must be in the subscription; a template's
        // recommendation simply leaves out the ones that are not.
        if ($chosen) {
            $config->assertLicensed($modules);
        } else {
            $modules = array_values(array_filter($modules, fn (string $m) => $config->isLicensed($m)));
        }

        return $this->tenant->forCompany($company, fn () => DB::transaction(function () use ($company, $type, $template, $modules, $settings, $actor) {
            $before = $company->only(['business_type', 'modules']);
            $current = BusinessConfig::of($company)->settings();

            $company->forceFill([
                'business_type' => $type,
                'modules' => $modules,
                'erp_settings' => array_replace($current, $template['settings'], [
                    // A re-run keeps the fields a company has already defined.
                    'product_fields' => $current['product_fields'] ?: $template['product_fields'],
                    'product_defaults' => $template['product_defaults'],
                ], $settings),
                'setup_completed_at' => $company->setup_completed_at ?? now(),
            ])->save();

            $counts = ['units' => 0, 'categories' => 0, 'warehouses' => 0, 'accounts' => 0];

            foreach ($template['units'] as $unit) {
                $counts['units'] += (int) Unit::firstOrCreate(['code' => $unit['code']], [...$unit, 'company_id' => $company->id])->wasRecentlyCreated;
            }

            foreach ($template['categories'] as $name) {
                $counts['categories'] += (int) ProductCategory::firstOrCreate(['name' => $name], ['company_id' => $company->id])->wasRecentlyCreated;
            }

            if (! Warehouse::query()->exists()) {
                Warehouse::create([
                    'company_id' => $company->id,
                    'code' => 'MAIN',
                    'name' => 'Main store',
                    'type' => in_array($type, ['retail', 'supermarket', 'pharmacy'], true) ? 'shop' : 'warehouse',
                    'branch' => $company->city,
                ]);
                $counts['warehouses'] = 1;
            }

            if (in_array('accounting', $modules, true)) {
                $counts['accounts'] = $this->chart->seed($company);
            }

            $this->audit->log(
                'erp.setup',
                "Configured the business as {$template['label']}",
                $company,
                $before,
                $company->only(['business_type', 'modules']),
                actor: $actor,
            );

            return $counts;
        }));
    }
}
