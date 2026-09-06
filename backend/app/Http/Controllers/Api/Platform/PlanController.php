<?php

namespace App\Http\Controllers\Api\Platform;

use App\Http\Controllers\Controller;
use App\Http\Resources\PlanResource;
use App\Models\Plan;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class PlanController extends Controller
{
    public function __construct(private readonly AuditLogger $audit) {}

    public function index()
    {
        return PlanResource::collection(
            Plan::withCount('companies')->orderBy('sort_order')->get()
        );
    }

    public function store(Request $request)
    {
        $plan = Plan::create($this->rules($request));

        $this->audit->log('platform.plan_created', "Created plan {$plan->name}", $plan);

        return (new PlanResource($plan))->response()->setStatusCode(201);
    }

    public function update(Request $request, Plan $plan)
    {
        $before = $plan->only(['price', 'max_users', 'is_active']);
        $plan->update($this->rules($request, $plan->id));

        $this->audit->log(
            'platform.plan_updated',
            "Updated plan {$plan->name}",
            $plan,
            $before,
            $plan->only(['price', 'max_users', 'is_active']),
        );

        return new PlanResource($plan->fresh());
    }

    public function destroy(Plan $plan)
    {
        abort_if($plan->companies()->exists(), 422, 'Companies are on this plan. Deactivate it instead of deleting it.');

        $name = $plan->name;
        $plan->delete();

        $this->audit->log('platform.plan_deleted', "Deleted plan {$name}", null);

        return response()->json(['message' => "Plan {$name} deleted."]);
    }

    private function rules(Request $request, ?int $ignoreId = null): array
    {
        return $request->validate([
            'code' => ['required', 'string', 'max:40', Rule::unique('plans')->ignore($ignoreId)],
            'name' => ['required', 'string', 'max:80'],
            'name_sw' => ['nullable', 'string', 'max:80'],
            'blurb' => ['nullable', 'string', 'max:255'],
            'blurb_sw' => ['nullable', 'string', 'max:255'],
            'price' => ['required', 'numeric', 'min:0'],
            'currency' => ['nullable', 'string', 'size:3'],
            'billing_cycle' => ['required', Rule::in(['monthly', 'annual'])],
            'max_users' => ['nullable', 'integer', 'min:1'],
            'max_vouchers_per_month' => ['nullable', 'integer', 'min:1'],
            'max_departments' => ['nullable', 'integer', 'min:1'],
            'max_approval_levels' => ['nullable', 'integer', 'min:1'],
            'storage_mb' => ['nullable', 'integer', 'min:1'],
            'trial_days' => ['nullable', 'integer', 'min:0', 'max:365'],
            'features' => ['nullable', 'array'],
            'is_active' => ['nullable', 'boolean'],
            'is_public' => ['nullable', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
        ]);
    }
}
