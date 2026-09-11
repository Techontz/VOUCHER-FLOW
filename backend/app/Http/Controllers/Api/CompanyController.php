<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\CompanyResource;
use App\Services\AuditLogger;
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
        $this->authorizeAdmin($request);
        $company = $this->tenant->company();

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:180'],
            'legal_name' => ['nullable', 'string', 'max:180'],
            'email' => ['sometimes', 'email', 'max:180'],
            'phone' => ['nullable', 'string', 'max:40'],
            'address' => ['nullable', 'string', 'max:255'],
            'website' => ['nullable', 'string', 'max:180'],
            'tin' => ['nullable', 'string', 'max:40'],
            'registration_number' => ['nullable', 'string', 'max:60'],
            'country' => ['nullable', 'string', 'size:2'],
            'currency' => ['nullable', 'string', 'size:3'],
            'locale' => ['nullable', Rule::in(config('vouchflow.locales'))],
            'timezone' => ['nullable', 'string', 'max:60'],
            'settings' => ['nullable', 'array'],
        ]);

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

    /** Logo, colours, theme and the footer line printed on every voucher. */
    public function updateBranding(Request $request)
    {
        $this->authorizeAdmin($request);
        $company = $this->tenant->company();

        $data = $request->validate([
            'primary_color' => ['nullable', 'string', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'accent_color' => ['nullable', 'string', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'theme' => ['nullable', Rule::in(['light', 'dark'])],
            'voucher_header_text' => ['nullable', 'string', 'max:255'],
            'voucher_footer_text' => ['nullable', 'string', 'max:500'],
            'logo' => ['nullable', 'image', 'max:2048'],
            'logo_mark' => ['nullable', 'image', 'max:1024'],
            'remove_logo' => ['nullable', 'boolean'],
            'remove_logo_mark' => ['nullable', 'boolean'],

            // Printed on a bank voucher as the account the money is drawn on.
            'bank_name' => ['nullable', 'string', 'max:120'],
            'bank_account_name' => ['nullable', 'string', 'max:180'],
            'bank_account_number' => ['nullable', 'string', 'max:64'],
            'bank_branch' => ['nullable', 'string', 'max:120'],
        ]);

        if ($request->boolean('remove_logo') && $company->logo_path) {
            Storage::disk('public')->delete($company->logo_path);
            $company->logo_path = null;
        }

        if ($request->hasFile('logo')) {
            if ($company->logo_path) {
                Storage::disk('public')->delete($company->logo_path);
            }

            $company->logo_path = $request->file('logo')->store("companies/{$company->id}/branding", 'public');
        }

        if ($request->boolean('remove_logo_mark') && $company->logo_mark_path) {
            Storage::disk('public')->delete($company->logo_mark_path);
            $company->logo_mark_path = null;
        }

        if ($request->hasFile('logo_mark')) {
            if ($company->logo_mark_path) {
                Storage::disk('public')->delete($company->logo_mark_path);
            }

            $company->logo_mark_path = $request->file('logo_mark')->store("companies/{$company->id}/branding", 'public');
        }

        $company->fill(collect($data)->only([
            'primary_color', 'accent_color', 'theme',
            'voucher_header_text', 'voucher_footer_text',
            'bank_name', 'bank_account_name', 'bank_account_number', 'bank_branch',
        ])->filter(fn ($v) => $v !== null)->all())->save();

        $this->audit->log('company.branding_updated', "Updated branding for {$company->name}", $company);

        return new CompanyResource($company->fresh()->load('plan'));
    }

    public function usage()
    {
        $company = $this->tenant->company();
        abort_unless($company, 404);

        return response()->json(['data' => $this->limits->snapshot($company)]);
    }

    private function authorizeAdmin(Request $request): void
    {
        abort_unless($request->user()->isAdmin(), 403, 'Only an administrator may change company settings.');
    }
}
