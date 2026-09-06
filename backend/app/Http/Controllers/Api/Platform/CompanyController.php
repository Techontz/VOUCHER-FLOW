<?php

namespace App\Http\Controllers\Api\Platform;

use App\Http\Controllers\Controller;
use App\Http\Resources\CompanyResource;
use App\Http\Resources\InvoiceResource;
use App\Http\Resources\SubscriptionResource;
use App\Http\Resources\UserResource;
use App\Models\Company;
use App\Models\Plan;
use App\Models\User;
use App\Models\Voucher;
use App\Services\AuditLogger;
use App\Services\CompanyProvisioner;
use App\Services\PaymentGateway;
use App\Services\UsageLimits;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Platform administration of every tenant. Super admin only. */
class CompanyController extends Controller
{
    public function __construct(
        private readonly CompanyProvisioner $provisioner,
        private readonly PaymentGateway $payments,
        private readonly UsageLimits $limits,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request)
    {
        $companies = Company::query()
            ->with('plan')
            ->withCount(['users', 'vouchers'])
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                ->where('name', 'like', "%{$v}%")->orWhere('email', 'like', "%{$v}%")))
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('plan_id'), fn ($q, $v) => $q->where('plan_id', $v))
            ->orderBy('name')
            ->paginate((int) $request->query('per_page', 25))
            ->withQueryString();

        return CompanyResource::collection($companies);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'company_name' => ['required', 'string', 'max:180'],
            'business_email' => ['required', 'email', 'max:180'],
            'phone' => ['nullable', 'string', 'max:40'],
            'address' => ['nullable', 'string', 'max:255'],
            'country' => ['nullable', 'string', 'size:2'],
            'currency' => ['nullable', 'string', 'size:3'],
            'plan_id' => ['nullable', 'integer', Rule::exists('plans', 'id')],

            'admin_name' => ['required', 'string', 'max:180'],
            'admin_email' => ['required', 'email', 'max:180'],
            'admin_password' => ['required', 'string', 'min:8'],
        ]);

        ['company' => $company] = $this->provisioner->provision(
            [
                'name' => $data['company_name'],
                'email' => $data['business_email'],
                'phone' => $data['phone'] ?? null,
                'address' => $data['address'] ?? null,
                'country' => $data['country'] ?? 'TZ',
                'currency' => $data['currency'] ?? 'TZS',
            ],
            [
                'name' => $data['admin_name'],
                'email' => $data['admin_email'],
                'password' => $data['admin_password'],
            ],
            isset($data['plan_id']) ? Plan::find($data['plan_id']) : null,
        );

        return (new CompanyResource($company->load('plan')))->response()->setStatusCode(201);
    }

    public function show(Company $company)
    {
        $company->load('plan')->loadCount(['users', 'vouchers']);

        // Every read of this tenant's data happens inside its own scope.
        $detail = $this->tenant->forCompany($company, fn () => [
            'usage' => $this->limits->snapshot($company),
            'subscription' => $company->activeSubscription()
                ? new SubscriptionResource($company->activeSubscription()->load('plan'))
                : null,
            'invoices' => InvoiceResource::collection($company->invoices()->latest('id')->limit(10)->get()),
            'admins' => UserResource::collection(
                User::forTenant($company->id)->where('role', 'company_admin')->get()
            ),
            'vouchers' => [
                'total' => Voucher::count(),
                'pending' => Voucher::where('status', Voucher::STATUS_IN_REVIEW)->count(),
                'approved' => Voucher::where('status', Voucher::STATUS_APPROVED)->count(),
                'rejected' => Voucher::where('status', Voucher::STATUS_REJECTED)->count(),
                'value' => (float) Voucher::where('status', Voucher::STATUS_APPROVED)->sum('amount'),
            ],
        ]);

        return (new CompanyResource($company))->additional($detail);
    }

    public function update(Request $request, Company $company)
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:180'],
            'email' => ['sometimes', 'email', 'max:180'],
            'phone' => ['nullable', 'string', 'max:40'],
            'address' => ['nullable', 'string', 'max:255'],
            'status' => ['sometimes', Rule::in(['trial', 'active', 'past_due', 'suspended', 'cancelled'])],
            'plan_id' => ['nullable', 'integer', Rule::exists('plans', 'id')],
            'trial_ends_at' => ['nullable', 'date'],
            'current_period_end' => ['nullable', 'date'],
        ]);

        $before = $company->only(['status', 'plan_id']);
        $company->update($data);

        // Suspending a tenant must end its sessions immediately.
        if (($data['status'] ?? null) === 'suspended') {
            User::forTenant($company->id)->get()->each(fn (User $u) => $u->tokens()->delete());
        }

        $this->audit->log(
            'platform.company_updated',
            "Updated company {$company->name}",
            $company,
            $before,
            $company->only(['status', 'plan_id']),
            $company->id,
        );

        return new CompanyResource($company->fresh()->load('plan'));
    }

    public function suspend(Request $request, Company $company)
    {
        $company->forceFill(['status' => 'suspended'])->save();
        User::forTenant($company->id)->get()->each(fn (User $u) => $u->tokens()->delete());

        $this->audit->log('platform.company_suspended', "Suspended company {$company->name}", $company,
            ['status' => 'active'], ['status' => 'suspended'], $company->id);

        return new CompanyResource($company->fresh()->load('plan'));
    }

    public function activate(Request $request, Company $company)
    {
        $company->forceFill(['status' => 'active'])->save();

        $this->audit->log('platform.company_activated', "Reactivated company {$company->name}", $company,
            ['status' => 'suspended'], ['status' => 'active'], $company->id);

        return new CompanyResource($company->fresh()->load('plan'));
    }

    public function destroy(Request $request, Company $company)
    {
        $name = $company->name;
        User::forTenant($company->id)->get()->each(fn (User $u) => $u->tokens()->delete());
        $company->delete();

        $this->audit->log('platform.company_deleted', "Deleted company {$name}", null, null, null, null);

        return response()->json(['message' => "Company {$name} deleted."]);
    }

    /** Moves a tenant onto another plan without taking payment. */
    public function changePlan(Request $request, Company $company)
    {
        $data = $request->validate([
            'plan_id' => ['required', 'integer', Rule::exists('plans', 'id')],
            'billing_cycle' => ['nullable', Rule::in(['monthly', 'annual'])],
        ]);

        $plan = Plan::findOrFail($data['plan_id']);

        $subscription = $this->tenant->forCompany(
            $company,
            fn () => $this->payments->subscribe($company, $plan, $data['billing_cycle'] ?? $plan->billing_cycle),
        );

        return response()->json([
            'message' => "{$company->name} moved to the {$plan->name} plan.",
            'subscription' => new SubscriptionResource($subscription->load('plan')),
        ]);
    }
}
