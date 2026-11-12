<?php

namespace App\Http\Controllers\Api\Erp;

use App\Http\Controllers\Controller;
use App\Models\Erp\Customer;
use App\Models\Erp\JournalEntry;
use App\Models\Erp\Product;
use App\Models\Erp\StockBalance;
use App\Models\Erp\StockDocument;
use App\Models\Erp\Supplier;
use App\Models\Erp\Warehouse;
use App\Services\AuditLogger;
use App\Services\Erp\BusinessSetup;
use App\Support\Erp\BusinessConfig;
use App\Support\Erp\BusinessTemplates;
use App\Support\Erp\Permissions;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * The business setup wizard and the company's ERP configuration, plus the
 * overview every ERP screen opens on.
 */
class SetupController extends Controller
{
    public function __construct(
        private readonly TenantContext $tenant,
        private readonly Permissions $permissions,
        private readonly AuditLogger $audit,
    ) {}

    /** The templates and modules the wizard offers. */
    public function templates(): JsonResponse
    {
        return response()->json([
            'data' => collect(BusinessTemplates::all())
                ->map(fn ($t, $key) => ['key' => $key, ...$t])
                ->values(),
            'modules' => collect(BusinessTemplates::modules())
                ->map(fn ($m, $key) => ['key' => $key, ...$m])
                ->values(),
        ]);
    }

    /** What this company runs, and what the caller may do in it. */
    public function show(Request $request): JsonResponse
    {
        $company = $this->tenant->company();
        abort_unless($company, 404);
        $config = BusinessConfig::of($company);

        return response()->json(['data' => [
            'business_type' => $company->business_type,
            'business_label' => BusinessTemplates::get($company->business_type)['label'] ?? null,
            'is_set_up' => $config->isSetUp(),
            'setup_completed_at' => $company->setup_completed_at?->toIso8601String(),
            'modules' => $config->modules(),
            'licensed_modules' => $config->licensedModules(),
            'live_modules' => array_keys(array_filter(BusinessTemplates::modules(), fn ($m) => $m['live'])),
            'settings' => $config->settings(),
            'permissions' => $this->permissions->for($request->user()),
        ]]);
    }

    public function apply(Request $request, BusinessSetup $setup): JsonResponse
    {
        $data = $request->validate([
            'business_type' => ['required', Rule::in(BusinessTemplates::keys())],
            'modules' => ['nullable', 'array'],
            'modules.*' => ['string', Rule::in(array_keys(BusinessTemplates::modules()))],
            'settings' => ['nullable', 'array'],
            ...$this->settingRules('settings.'),
        ]);

        $created = $setup->apply(
            $this->tenant->company(),
            $data['business_type'],
            $data['modules'] ?? null,
            $data['settings'] ?? [],
            $request->user(),
        );

        $this->permissions->forget();

        return response()->json(['message' => 'Your business is set up.', 'created' => $created, ...$this->show($request)->getData(true)]);
    }

    /** Settings and modules, edited after setup without re-running the template. */
    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'modules' => ['sometimes', 'array'],
            'modules.*' => ['string', Rule::in(array_keys(BusinessTemplates::modules()))],
            ...$this->settingRules(''),
        ]);

        $company = $this->tenant->company();
        $before = $company->only(['modules', 'erp_settings']);
        $settings = collect($data)->except('modules')->all();

        if (array_key_exists('modules', $data)) {
            BusinessConfig::of($company)->assertLicensed($data['modules']);
        }

        $company->forceFill([
            'modules' => array_key_exists('modules', $data)
                ? array_values(array_unique(['vouchflow', ...$data['modules']]))
                : $company->modules,
            'erp_settings' => array_replace(BusinessConfig::of($company)->settings(), $settings),
        ])->save();

        $this->audit->log('erp.settings.updated', 'Updated business settings', $company, $before, $company->only(['modules', 'erp_settings']));

        return $this->show($request);
    }

    /** The figures the ERP home opens on, limited to what the caller may see. */
    public function overview(Request $request): JsonResponse
    {
        $user = $request->user();
        $config = BusinessConfig::of($this->tenant->company());
        $out = ['is_set_up' => $config->isSetUp(), 'modules' => $config->modules()];

        if ($config->hasModule('inventory') && $user->hasPermission('inventory.view')) {
            $value = StockBalance::query()->selectRaw('COALESCE(SUM(quantity * average_cost), 0) AS v')->value('v');
            $low = Product::query()
                ->where('is_active', true)->where('type', '!=', 'service')->where('reorder_level', '>', 0)
                ->whereRaw('reorder_level >= (SELECT COALESCE(SUM(b.quantity), 0) FROM stock_balances b WHERE b.product_id = products.id)')
                ->count();

            $out['inventory'] = [
                'stock_value' => round((float) $value, 2),
                'products' => Product::query()->where('is_active', true)->count(),
                'warehouses' => Warehouse::query()->where('is_active', true)->count(),
                'low_stock' => $low,
                'drafts' => StockDocument::query()->where('status', StockDocument::STATUS_DRAFT)->count(),
                'movements_7d' => DB::table('stock_movements')
                    ->where('company_id', $this->tenant->id())
                    ->where('movement_date', '>=', now()->subDays(6)->toDateString())
                    ->selectRaw('movement_date AS day, COUNT(*) AS count')
                    ->groupBy('movement_date')->orderBy('movement_date')->get(),
                'recent' => StockDocument::query()->with('warehouse:id,name')
                    ->latest('id')->limit(6)
                    ->get(['id', 'number', 'type', 'status', 'warehouse_id', 'document_date']),
            ];
        }

        if ($user->hasPermission('customers.view')) {
            $out['customers'] = Customer::query()->where('is_active', true)->count();
        }

        if ($user->hasPermission('suppliers.view')) {
            $out['suppliers'] = Supplier::query()->where('is_active', true)->count();
        }

        if ($config->hasModule('accounting') && $user->hasPermission('accounting.view')) {
            $out['accounting'] = [
                'journals_this_month' => JournalEntry::query()->where('entry_date', '>=', now()->startOfMonth()->toDateString())->count(),
            ];
        }

        return response()->json(['data' => $out]);
    }

    /** @return array<string, list<mixed>> */
    private function settingRules(string $prefix): array
    {
        return [
            "{$prefix}allow_negative_stock" => ['sometimes', 'boolean'],
            "{$prefix}base_currency" => ['sometimes', 'string', 'size:3'],
            "{$prefix}default_tax_rate" => ['sometimes', 'numeric', 'min:0', 'max:100'],
            "{$prefix}fiscal_year_start" => ['sometimes', 'regex:/^\d{2}-\d{2}$/'],
            "{$prefix}expiry_alert_days" => ['sometimes', 'integer', 'min:0', 'max:730'],
            "{$prefix}product_fields" => ['sometimes', 'array', 'max:30'],
            "{$prefix}product_fields.*.key" => ['required', 'string', 'max:40', 'regex:/^[a-z][a-z0-9_]*$/'],
            "{$prefix}product_fields.*.label" => ['required', 'string', 'max:80'],
            "{$prefix}product_fields.*.type" => ['required', Rule::in(['text', 'number', 'date', 'boolean'])],
            "{$prefix}product_defaults" => ['sometimes', 'array'],
            "{$prefix}product_defaults.track_batches" => ['sometimes', 'boolean'],
            "{$prefix}product_defaults.track_expiry" => ['sometimes', 'boolean'],
            "{$prefix}product_defaults.track_serials" => ['sometimes', 'boolean'],
        ];
    }
}
