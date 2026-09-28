<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\CompanyResource;
use App\Models\Company;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Notifier;
use App\Services\VoucherDocument;
use App\Services\VoucherTemplateManager;
use App\Support\TenantContext;
use App\Support\VoucherTemplates;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

/**
 * Voucher designs: the catalogue, sample previews, a company's own (limited)
 * change and the platform's unlimited override.
 */
class VoucherTemplateController extends Controller
{
    /** Stands in for a logo the browser has not uploaded yet; the client swaps it in. */
    public const LOGO_PLACEHOLDER = '__VF_LOGO__';

    public function __construct(
        private readonly VoucherDocument $document,
        private readonly VoucherTemplateManager $templates,
        private readonly TenantContext $tenant,
        private readonly Notifier $notifier,
        private readonly AuditLogger $audit,
    ) {}

    /** Public: the designs on offer, for registration. */
    public function index()
    {
        return response()->json([
            'data' => VoucherTemplates::all(),
            'default' => VoucherTemplates::DEFAULT,
            'self_service_changes' => VoucherTemplates::selfServiceChanges(),
        ]);
    }

    /**
     * Public: the sample voucher rendered in one design, or all of them, in
     * the colours and name typed so far. No company exists yet, so nothing
     * here reads or writes tenant data.
     */
    public function preview(Request $request)
    {
        $data = $request->validate([
            'template' => ['nullable', Rule::in(VoucherTemplates::keys())],
            'locale' => ['nullable', Rule::in(config('vouchflow.locales'))],
            'name' => ['nullable', 'string', 'max:180'],
            'address' => ['nullable', 'string', 'max:255'],
            'phone' => ['nullable', 'string', 'max:40'],
            'email' => ['nullable', 'string', 'max:180'],
            'website' => ['nullable', 'string', 'max:180'],
            'tin' => ['nullable', 'string', 'max:40'],
            'voucher_footer_text' => ['nullable', 'string', 'max:500'],
            'primary_color' => ['nullable', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'secondary_color' => ['nullable', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'with_logo' => ['nullable', 'boolean'],
        ]);

        $brand = collect($data)->only(['name', 'address', 'phone', 'email', 'website', 'tin', 'voucher_footer_text', 'primary_color', 'secondary_color'])
            ->filter(fn ($v) => filled($v))
            ->all();

        if ($request->boolean('with_logo')) {
            $brand['logo'] = self::LOGO_PLACEHOLDER;
        }

        return $this->previews($data['template'] ?? null, $brand, $data['locale'] ?? app()->getLocale());
    }

    /* ------------------------------------------------------------ tenant */

    public function show()
    {
        $company = $this->company();

        return response()->json($this->state($company, $this->canManage($company)));
    }

    /** The sample voucher in the company's own letterhead. */
    public function companyPreview(Request $request)
    {
        $company = $this->company();

        return $this->companyPreviews($request, $company);
    }

    public function update(Request $request)
    {
        $company = $this->company();

        if (! request()->user()->isCompanyAdmin() || ! $this->canManage($company)) {
            throw new AccessDeniedHttpException('Only the company administrator can change the voucher template.');
        }

        $data = $request->validate([
            'template' => ['required', 'string'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        $company = $this->templates->changeByCompany($company, $data['template'], $request->user(), $data['reason'] ?? null);

        return response()->json($this->state($company, true) + [
            'company' => new CompanyResource($company->load('plan')),
        ]);
    }

    /**
     * Once the company's own change is spent, the administrator asks the
     * platform instead. Every super admin is told in-app; the platform then
     * uses its override. Nothing about the design changes here.
     */
    public function requestChange(Request $request)
    {
        $company = $this->company();
        $actor = $request->user();

        if (! $actor->isCompanyAdmin() || ! $this->canManage($company)) {
            throw new AccessDeniedHttpException('Only the company administrator can request a template change.');
        }

        $data = $request->validate([
            'template' => ['required', Rule::in(VoucherTemplates::keys())],
            'reason' => ['required', 'string', 'min:5', 'max:500'],
        ]);

        $current = VoucherTemplates::name($company->voucher_template);
        $wanted = VoucherTemplates::name($data['template']);
        $wantedSw = VoucherTemplates::name($data['template'], 'sw');

        $operators = User::withoutGlobalScopes()->where('role', User::ROLE_SUPER_ADMIN)->where('status', 'active')->get();

        foreach ($operators as $operator) {
            $this->notifier->toUser(
                $operator,
                'voucher_template.change_requested',
                "{$company->name} asks to change its voucher template",
                "{$company->name} inaomba kubadilisha kiolezo cha vocha",
                "{$actor->name}: {$current} → {$wanted}. {$data['reason']}",
                "{$actor->name}: ".VoucherTemplates::name($company->voucher_template, 'sw')." → {$wantedSw}. {$data['reason']}",
                null,
                'ph-layout',
                "/platform/companies/{$company->id}",
            );
        }

        $this->audit->log(
            'company.voucher_template_change_requested',
            "Requested a voucher template change from {$current} to {$wanted} — {$data['reason']}",
            $company,
            null,
            ['requested_template' => $data['template']],
            $company->id,
            $actor,
        );

        return response()->json(['message' => 'Your request has been sent to the VouchFlow platform team.']);
    }

    /* ---------------------------------------------------------- platform */

    public function platformShow(Company $company)
    {
        return response()->json($this->state($company, true));
    }

    public function platformPreview(Request $request, Company $company)
    {
        return $this->companyPreviews($request, $company);
    }

    public function platformUpdate(Request $request, Company $company)
    {
        $data = $request->validate([
            'template' => ['required', 'string'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        $company = $this->templates->changeByPlatform($company, $data['template'], $request->user(), $data['reason'] ?? null);

        return response()->json($this->state($company, true));
    }

    /* ----------------------------------------------------------- helpers */

    /** @return array<string, mixed> */
    private function state(Company $company, bool $withHistory): array
    {
        $key = VoucherTemplates::resolve($company->voucher_template);

        return [
            'template' => $key,
            'template_name' => VoucherTemplates::name($key),
            'changes_used' => (int) $company->voucher_template_changes_used,
            'changes_allowed' => VoucherTemplates::selfServiceChanges(),
            'changes_remaining' => $company->voucherTemplateChangesRemaining(),
            'templates' => VoucherTemplates::all(),
            'history' => $withHistory ? $this->templates->history($company) : [],
        ];
    }

    private function companyPreviews(Request $request, Company $company)
    {
        $data = $request->validate([
            'template' => ['nullable', Rule::in(VoucherTemplates::keys())],
            'locale' => ['nullable', Rule::in(config('vouchflow.locales'))],
        ]);

        $brand = [
            'name' => $company->documentName(),
            'address' => $company->address,
            'phone' => $company->phone,
            'email' => $company->email,
            'website' => $company->website,
            'tin' => $company->tin,
            'primary_color' => $company->primary_color,
            'secondary_color' => $company->secondary_color,
            'logo' => $company->logoUrl(),
            'voucher_header_text' => $company->voucher_header_text,
            'voucher_footer_text' => $company->voucher_footer_text ?: null,
        ];

        return $this->previews($data['template'] ?? null, array_filter($brand, fn ($v) => filled($v)), $data['locale'] ?? app()->getLocale());
    }

    private function previews(?string $template, array $brand, string $locale)
    {
        $keys = $template ? [$template] : VoucherTemplates::keys();

        return response()->json([
            'data' => array_map(fn (string $key) => [
                'key' => $key,
                'html' => $this->document->renderSample($key, $brand, $locale, 'html'),
            ], $keys),
            'logo_placeholder' => self::LOGO_PLACEHOLDER,
        ]);
    }

    private function company(): Company
    {
        $company = $this->tenant->company();
        abort_unless($company, 404, 'No company context.');

        return $company;
    }

    private function canManage(Company $company): bool
    {
        return request()->user()->can('brand', $company);
    }
}
