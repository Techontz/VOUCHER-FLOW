<?php

namespace App\Support\Erp;

use App\Models\Company;
use RuntimeException;

/**
 * Reads a company's ERP configuration. Every module asks this rather than the
 * raw JSON columns, so defaults live in one place.
 *
 * A company that has not run the setup wizard has VouchFlow and nothing else:
 * existing tenants see no change until their administrator opts in.
 */
class BusinessConfig
{
    /** @var array<string, mixed> */
    public const DEFAULT_SETTINGS = [
        'allow_negative_stock' => false,
        'costing_method' => 'weighted_average',
        'base_currency' => 'TZS',
        'default_tax_rate' => 18,
        'fiscal_year_start' => '01-01',
        'expiry_alert_days' => 60,
        'product_fields' => [],
        'product_defaults' => ['track_batches' => false, 'track_expiry' => false, 'track_serials' => false],
    ];

    public function __construct(private readonly Company $company) {}

    public static function of(Company $company): self
    {
        return new self($company);
    }

    public function isSetUp(): bool
    {
        return $this->company->setup_completed_at !== null;
    }

    /**
     * The apps the company runs: those its administrator switched on that its
     * subscription also allows. VouchFlow is always among them.
     *
     * @return list<string>
     */
    public function modules(): array
    {
        $enabled = $this->enabledModules();

        if (! is_array($this->company->licensed_modules)) {
            return $enabled;
        }

        return array_values(array_intersect($enabled, $this->licensedModules()));
    }

    public function hasModule(string $module): bool
    {
        return in_array($module, $this->modules(), true);
    }

    /**
     * What the administrator switched on, whether or not the subscription
     * still allows it. Only the setup screens need this; everything else asks
     * modules().
     *
     * @return list<string>
     */
    public function enabledModules(): array
    {
        $stored = $this->company->modules;

        return array_values(array_unique(['vouchflow', ...(is_array($stored) ? $stored : [])]));
    }

    /**
     * The apps the subscription allows, in catalogue order. A company with no
     * licence recorded predates licensing and keeps every app.
     *
     * @return list<string>
     */
    public function licensedModules(): array
    {
        $stored = $this->company->licensed_modules;
        $all = array_keys(BusinessTemplates::modules());

        if (! is_array($stored)) {
            return $all;
        }

        return array_values(array_intersect($all, ['vouchflow', ...$stored]));
    }

    public function isLicensed(string $module): bool
    {
        $stored = $this->company->licensed_modules;

        return $module === 'vouchflow' || ! is_array($stored) || in_array($module, $stored, true);
    }

    /**
     * Refuses to switch on an app the subscription does not include.
     *
     * @param  list<string>  $modules
     */
    public function assertLicensed(array $modules): void
    {
        $missing = array_values(array_filter($modules, fn (string $m) => ! $this->isLicensed($m)));

        if ($missing) {
            $catalogue = BusinessTemplates::modules();
            $labels = array_map(fn (string $m) => $catalogue[$m]['label'] ?? $m, $missing);

            throw new RuntimeException(
                implode(', ', $labels).(count($labels) === 1 ? ' is' : ' are')
                .' not in your subscription. Ask VouchFlow to add '.(count($labels) === 1 ? 'it' : 'them').' to your plan.'
            );
        }
    }

    /**
     * The value to store in companies.licensed_modules for a set of apps:
     * VouchFlow added, unknown keys dropped, catalogue order, and NULL when the
     * set is every app, so apps added to the catalogue later are included too.
     *
     * @param  list<string>|null  $apps  null means every app
     * @return list<string>|null
     */
    public static function licenceFor(?array $apps): ?array
    {
        if ($apps === null) {
            return null;
        }

        $all = array_keys(BusinessTemplates::modules());
        $licence = array_values(array_intersect($all, ['vouchflow', ...$apps]));

        return count($licence) === count($all) ? null : $licence;
    }

    /** @return array<string, mixed> */
    public function settings(): array
    {
        $stored = $this->company->erp_settings;

        return array_replace(self::DEFAULT_SETTINGS, is_array($stored) ? $stored : []);
    }

    public function setting(string $key): mixed
    {
        return $this->settings()[$key] ?? null;
    }

    public function allowsNegativeStock(): bool
    {
        return (bool) $this->setting('allow_negative_stock');
    }

    /** Stock postings reach the general ledger only when accounting is switched on. */
    public function postsToLedger(): bool
    {
        return $this->hasModule('accounting');
    }
}
