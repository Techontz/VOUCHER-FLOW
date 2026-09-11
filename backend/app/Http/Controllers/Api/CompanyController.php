<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\CompanyResource;
use App\Models\Company;
use App\Services\AuditLogger;
use App\Services\CompanyBranding;
use App\Services\UsageLimits;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;

/** The tenant's own profile, branding and settings. */
class CompanyController extends Controller
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly UsageLimits $limits,
        private readonly TenantContext $tenant,
        private readonly CompanyBranding $branding,
    ) {}

    public function show(Request $request)
    {
        $company = $this->tenant->company();
        abort_unless($company, 404, 'No company context.');

        return (new CompanyResource($company->load('plan')->loadCount(['users', 'vouchers'])))
            ->additional(['usage' => $this->limits->snapshot($company)]);
    }

    public function update(Request $request)
    {
        $company = $this->requireCompany($request);

        // Rules come from the model, so this endpoint, the platform's
        // create-company screen and registration cannot drift apart.
        $data = $request->validate(Company::updateRules());

        $before = $company->only(['name', 'email', 'currency', 'locale']);
        $company->update($data);

        $this->audit->log(
            'company.updated',
            "Updated company profile for {$company->name}",
            $company,
            $before,
            $company->only(['name', 'email', 'currency', 'locale']),
        );

        return new CompanyResource($company->fresh()->load('plan'));
    }

    /**
     * Colours, letterhead wording, banking details and artwork.
     *
     * Accepts multipart so a screen can save text and a new logo in one action;
     * the dedicated logo endpoints below exist for the upload control, which
     * needs to replace artwork on its own without resubmitting the form.
     */
    public function updateBranding(Request $request)
    {
        $company = $this->requireCompany($request);

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

            'bank_name' => ['nullable', 'string', 'max:120'],
            'bank_account_name' => ['nullable', 'string', 'max:180'],
            'bank_account_number' => ['nullable', 'string', 'max:64'],
            'bank_branch' => ['nullable', 'string', 'max:120'],
            'swift_code' => ['nullable', 'string', 'max:24'],
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

        $company->fill(collect($data)->only([
            'primary_color', 'secondary_color', 'accent_color', 'theme',
            'voucher_header_text', 'voucher_footer_text',
            'bank_name', 'bank_account_name', 'bank_account_number', 'bank_branch', 'swift_code',
        ])->filter(fn ($v) => $v !== null)->all())->save();

        $this->audit->log('company.branding_updated', "Updated branding for {$company->name}", $company);

        return new CompanyResource($company->fresh()->load('plan'));
    }

    /** Replaces one piece of artwork. Used by the upload control. */
    public function storeLogo(Request $request)
    {
        $company = $this->requireCompany($request);

        $data = $request->validate([
            'logo' => ['required', ...Company::logoRules()],
            'slot' => ['nullable', Rule::in([CompanyBranding::SLOT_LOGO, CompanyBranding::SLOT_MARK])],
        ]);

        $this->branding->store(
            $company,
            $request->file('logo'),
            $data['slot'] ?? CompanyBranding::SLOT_LOGO,
        );

        return new CompanyResource($company->fresh()->load('plan'));
    }

    public function destroyLogo(Request $request)
    {
        $company = $this->requireCompany($request);

        $slot = $request->query('slot', CompanyBranding::SLOT_LOGO);
        abort_unless(
            in_array($slot, [CompanyBranding::SLOT_LOGO, CompanyBranding::SLOT_MARK], true),
            422,
            'Unknown logo slot.',
        );

        $this->branding->remove($company, $slot);

        return new CompanyResource($company->fresh()->load('plan'));
    }

    /**
     * The caller's own company, and the right to change it.
     *
     * The tenant scope already makes another company unreachable; the policy
     * decides whether this particular member may edit their own.
     */
    private function requireCompany(Request $request): Company
    {
        $company = $this->tenant->company();
        abort_unless($company, 404, 'No company context.');

        $this->authorize('update', $company);

        return $company;
    }

    public function usage()
    {
        $company = $this->tenant->company();
        abort_unless($company, 404);

        return response()->json(['data' => $this->limits->snapshot($company)]);
    }
}
