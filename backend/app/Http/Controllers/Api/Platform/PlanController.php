<?php

namespace App\Http\Controllers\Api\Platform;

use App\Http\Controllers\Controller;
use App\Http\Resources\PlanResource;
use App\Models\Plan;
use App\Services\AuditLogger;
use App\Support\Erp\BusinessTemplates;
use App\Support\PlatformSettings;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * The plans the platform sells: prices, limits, the apps each includes (or
 * lets the customer pick, at a price per app), and the order they appear in
 * on the public pricing page.
 */
class PlanController extends Controller
{
    /** What the audit trail records about a plan before and after a change. */
    private const TRACKED = ['name', 'price', 'price_yearly', 'max_users', 'max_vouchers_per_month', 'is_active', 'is_public', 'is_featured', 'sort_order', 'modules', 'allows_module_choice', 'price_per_module'];

    public function __construct(private readonly AuditLogger $audit) {}

    public function index()
    {
        return PlanResource::collection(
            Plan::withCount(['companies', 'subscriptions'])->orderBy('sort_order')->orderBy('id')->get()
        );
    }

    public function store(Request $request)
    {
        $data = $this->rules($request);
        // A new plan goes to the end of the list unless placed explicitly.
        $data['sort_order'] ??= ((int) Plan::max('sort_order')) + 1;

        $plan = Plan::create($data);

        $this->audit->log('platform.plan_created', "Created plan {$plan->name}", $plan, null, $plan->only(self::TRACKED));

        return (new PlanResource($plan->loadCount(['companies', 'subscriptions'])))->response()->setStatusCode(201);
    }

    public function update(Request $request, Plan $plan)
    {
        $before = $plan->only(self::TRACKED);
        $plan->update($this->rules($request, $plan->id));

        $this->audit->log(
            'platform.plan_updated',
            "Updated plan {$plan->name}",
            $plan,
            $before,
            $plan->only(self::TRACKED),
        );

        return new PlanResource($plan->fresh()->loadCount(['companies', 'subscriptions']));
    }

    /**
     * Deletes a plan nobody has ever been on. One with companies or billing
     * history behind it is archived instead, so invoices keep their plan.
     */
    public function destroy(Plan $plan)
    {
        if ($plan->companies()->exists() || $plan->subscriptions()->exists()) {
            throw new RuntimeException('This plan is in use by companies or their billing history. Archive it instead of deleting it.');
        }

        $name = $plan->name;
        $plan->delete();

        $this->audit->log('platform.plan_deleted', "Deleted plan {$name}", null);

        return response()->json(['message' => "Plan {$name} deleted."]);
    }

    /** Saves the pricing order: the ids in the order they should appear. */
    public function reorder(Request $request)
    {
        $data = $request->validate([
            'ids' => ['required', 'array', 'min:1'],
            'ids.*' => ['integer', 'distinct', Rule::exists('plans', 'id')],
        ]);

        $ids = array_values($data['ids']);

        if (count($ids) !== Plan::count()) {
            throw new RuntimeException('Send every plan when reordering, so none is left without a place.');
        }

        $before = Plan::orderBy('sort_order')->orderBy('id')->pluck('id')->all();

        DB::transaction(function () use ($ids) {
            foreach ($ids as $position => $id) {
                Plan::whereKey($id)->update(['sort_order' => $position + 1]);
            }
        });

        $this->audit->log('platform.plans_reordered', 'Reordered the plans', null, ['order' => $before], ['order' => $ids]);

        return $this->index();
    }

    private function rules(Request $request, ?int $ignoreId = null): array
    {
        $data = $request->validate([
            'code' => ['required', 'string', 'max:40', 'alpha_dash', Rule::unique('plans')->ignore($ignoreId)],
            'name' => ['required', 'string', 'max:80'],
            'name_sw' => ['nullable', 'string', 'max:80'],
            'blurb' => ['nullable', 'string', 'max:255'],
            'blurb_sw' => ['nullable', 'string', 'max:255'],
            'price' => ['required', 'numeric', 'min:0', 'max:9999999999'],
            'price_yearly' => ['nullable', 'numeric', 'min:0', 'max:9999999999'],
            'currency' => ['nullable', 'string', 'size:3'],
            'billing_cycle' => ['required', Rule::in(['monthly', 'annual'])],
            'max_users' => ['nullable', 'integer', 'min:1'],
            'max_vouchers_per_month' => ['nullable', 'integer', 'min:1'],
            'max_departments' => ['nullable', 'integer', 'min:1'],
            'max_approval_levels' => ['nullable', 'integer', 'min:1'],
            'storage_mb' => ['nullable', 'integer', 'min:1'],
            'trial_days' => ['nullable', 'integer', 'min:0', 'max:365'],
            'features' => ['nullable', 'array', 'max:20'],
            'features.*' => ['nullable', 'string', 'max:120'],
            'modules' => ['nullable', 'array'],
            'modules.*' => ['string', Rule::in(array_keys(BusinessTemplates::modules()))],
            'allows_module_choice' => ['nullable', 'boolean'],
            'price_per_module' => ['nullable', 'numeric', 'min:0', 'max:9999999999'],
            'is_active' => ['nullable', 'boolean'],
            'is_public' => ['nullable', 'boolean'],
            'is_featured' => ['nullable', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
        ]);

        // Columns that are never NULL take their default when left blank.
        foreach (['trial_days', 'is_active', 'is_public', 'is_featured', 'sort_order', 'allows_module_choice', 'price_per_module'] as $key) {
            if (array_key_exists($key, $data) && $data[$key] === null) {
                unset($data[$key]);
            }
        }

        if (! isset($data['trial_days']) && $ignoreId === null) {
            $data['trial_days'] = PlatformSettings::trialDays();
        }

        if (! empty($data['currency'])) {
            $data['currency'] = strtoupper($data['currency']);
        } elseif ($ignoreId === null) {
            $data['currency'] = PlatformSettings::currency();
        } else {
            unset($data['currency']);
        }

        // Every plan includes payment vouchers; it is the product itself. A
        // plan sent without a list of apps (null) offers every app, including
        // apps added to the catalogue later.
        if (array_key_exists('modules', $data) && $data['modules'] !== null) {
            $data['modules'] = array_values(array_unique(['vouchflow', ...$data['modules']]));
        }

        if (array_key_exists('features', $data)) {
            $data['features'] = array_values(array_filter(array_map(fn ($f) => trim((string) $f), $data['features'] ?? []), fn ($f) => $f !== ''));
        }

        return $data;
    }
}
