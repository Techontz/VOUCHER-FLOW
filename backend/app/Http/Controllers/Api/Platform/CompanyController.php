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
use App\Services\CompanyBranding;
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
        private readonly CompanyBranding $branding,
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

    /**
     * Stands up a whole tenant: company record, branding, first administrator,
     * default voucher types, a starting workflow and a trial.
     *
     * Accepts multipart so the logo arrives with the details rather than
     * requiring a second round trip — a company created without its artwork
     * spends its first minutes issuing unbranded vouchers.
     */
    public function store(Request $request)
    {
        $profile = [];
        foreach (Company::PROFILE_RULES as $field => $rule) {
            $profile['company.'.$field] = ['sometimes', ...$rule];
        }

        $data = $request->validate($profile + [
            'company.name' => ['required', 'string', 'max:180'],
            'company.email' => ['required', 'email', 'max:180'],

            'branding' => ['sometimes', 'array'],
            'branding.primary_color' => ['nullable', 'string', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'branding.secondary_color' => ['nullable', 'string', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'branding.accent_color' => ['nullable', 'string', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'branding.theme' => ['nullable', Rule::in(['light', 'dark'])],
            'branding.voucher_header_text' => ['nullable', 'string', 'max:255'],
            'branding.voucher_footer_text' => ['nullable', 'string', 'max:500'],

            'logo' => ['nullable', ...Company::logoRules()],
            'logo_mark' => ['nullable', ...Company::logoRules()],

            'plan_id' => ['nullable', 'integer', Rule::exists('plans', 'id')],

            'admin.name' => ['required', 'string', 'max:180'],
            'admin.email' => ['required', 'email', 'max:180', 'unique:users,email'],
            'admin.phone' => ['nullable', 'string', 'max:40'],
            'admin.job_title' => ['nullable', 'string', 'max:120'],
            'admin.password' => ['required', 'string', 'min:8'],
        ]);

        $company = $data['company'];
        $admin = $data['admin'];

        ['company' => $created] = $this->provisioner->provision(
            [
                'name' => $company['name'],
                'email' => $company['email'],
                'phone' => $company['phone'] ?? null,
                'address' => $company['address'] ?? null,
                'website' => $company['website'] ?? null,
                'legal_name' => $company['legal_name'] ?? null,
                'country' => $company['country'] ?? 'TZ',
                'currency' => $company['currency'] ?? 'TZS',
            ],
            [
                'name' => $admin['name'],
                'email' => $admin['email'],
                'password' => $admin['password'],
                'phone' => $admin['phone'] ?? null,
                'job_title' => $admin['job_title'] ?? 'Company Administrator',
            ],
            isset($data['plan_id']) ? Plan::find($data['plan_id']) : null,
        );

        // The remaining profile fields, and the brand, in the tenant's own row.
        $created->fill(collect($company)->except(['name', 'email'])->filter(fn ($v) => $v !== null)->all());
        $created->fill(collect($data['branding'] ?? [])->filter(fn ($v) => $v !== null)->all());
        $created->save();

        if ($request->hasFile('logo')) {
            $this->branding->store($created, $request->file('logo'), CompanyBranding::SLOT_LOGO);
        }

        if ($request->hasFile('logo_mark')) {
            $this->branding->store($created, $request->file('logo_mark'), CompanyBranding::SLOT_MARK);
        }

        $this->audit->log('company.created', "Created company {$created->name}", $created);

        return (new CompanyResource($created->fresh()->load('plan')))->response()->setStatusCode(201);
    }

    /** A tenant's branding, set by the platform on their behalf. */
    public function updateBranding(Request $request, Company $company)
    {
        $rules = [];
        foreach (Company::BRANDING_RULES as $field => $rule) {
            $rules[$field] = ['sometimes', ...$rule];
        }

        $data = $request->validate($rules + [
            'theme' => ['nullable', Rule::in(['light', 'dark'])],
            'logo' => ['nullable', ...Company::logoRules()],
            'logo_mark' => ['nullable', ...Company::logoRules()],
            'remove_logo' => ['nullable', 'boolean'],
            'remove_logo_mark' => ['nullable', 'boolean'],
        ]);

        if ($request->boolean('remove_logo')) {
            $this->branding->remove($company, CompanyBranding::SLOT_LOGO);
        }

        if ($request->boolean('remove_logo_mark')) {
            $this->branding->remove($company, CompanyBranding::SLOT_MARK);
        }

        if ($request->hasFile('logo')) {
            $this->branding->store($company, $request->file('logo'), CompanyBranding::SLOT_LOGO);
        }

        if ($request->hasFile('logo_mark')) {
            $this->branding->store($company, $request->file('logo_mark'), CompanyBranding::SLOT_MARK);
        }

        $company->fill(collect($data)->only(array_keys(Company::BRANDING_RULES))
            ->filter(fn ($v) => $v !== null)->all())->save();

        return new CompanyResource($company->fresh()->load('plan'));
    }

    public function storeLogo(Request $request, Company $company)
    {
        $request->validate([
            'logo' => ['required', ...Company::logoRules()],
            'slot' => ['nullable', Rule::in([CompanyBranding::SLOT_LOGO, CompanyBranding::SLOT_MARK])],
        ]);

        $this->branding->store(
            $company,
            $request->file('logo'),
            $request->input('slot', CompanyBranding::SLOT_LOGO),
        );

        return new CompanyResource($company->fresh()->load('plan'));
    }

    public function destroyLogo(Request $request, Company $company)
    {
        $slot = $request->query('slot', CompanyBranding::SLOT_LOGO);
        abort_unless(
            in_array($slot, [CompanyBranding::SLOT_LOGO, CompanyBranding::SLOT_MARK], true),
            422,
            'Unknown logo slot.',
        );

        $this->branding->remove($company, $slot);

        return new CompanyResource($company->fresh()->load('plan'));
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
        $data = $request->validate(Company::updateRules() + [
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
