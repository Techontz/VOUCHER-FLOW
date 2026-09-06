<?php

namespace App\Services;

use App\Models\Company;
use App\Models\Plan;
use App\Models\User;
use App\Models\VoucherType;
use App\Models\Workflow;
use App\Models\WorkflowStep;
use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Stands up a new tenant: the company record, its first administrator, the
 * default voucher types, a starting approval route and a free trial.
 */
class CompanyProvisioner
{
    public function __construct(
        private readonly TenantContext $tenant,
        private readonly PaymentGateway $payments,
        private readonly AuditLogger $audit,
    ) {}

    /** The routes offered in the workflow builder, mirroring the design's presets. */
    public const PRESETS = [
        'default' => [
            'name' => 'Sign then approve',
            'description' => 'Employee → HOD (sign) → Manager (approve)',
            'steps' => [
                ['name' => 'Request', 'name_sw' => 'Ombi', 'role' => 'employee', 'assignee_hint' => 'Voucher creator',
                    'can_sign' => false, 'can_approve' => false, 'can_reject' => false, 'can_request_changes' => false, 'can_print' => true],
                ['name' => 'Department review', 'name_sw' => 'Ukaguzi wa idara', 'role' => 'hod', 'assignee_hint' => 'Head of the requesting department',
                    'can_sign' => true, 'can_approve' => false, 'can_reject' => false, 'can_request_changes' => true, 'can_print' => true, 'requires_signature' => true],
                ['name' => 'Management approval', 'name_sw' => 'Idhini ya menejimenti', 'role' => 'manager', 'assignee_hint' => 'Approving manager',
                    'can_sign' => false, 'can_approve' => true, 'can_reject' => true, 'can_request_changes' => true, 'can_print' => true],
            ],
        ],
        'finance' => [
            'name' => 'Finance in the middle',
            'description' => 'Employee → HOD (sign) → Finance (approve) → Manager (approve & sign)',
            'steps' => [
                ['name' => 'Request', 'name_sw' => 'Ombi', 'role' => 'employee', 'assignee_hint' => 'Voucher creator',
                    'can_sign' => false, 'can_approve' => false, 'can_reject' => false, 'can_request_changes' => false, 'can_print' => true],
                ['name' => 'Department review', 'name_sw' => 'Ukaguzi wa idara', 'role' => 'hod', 'assignee_hint' => 'Head of the requesting department',
                    'can_sign' => true, 'can_approve' => false, 'can_reject' => false, 'can_request_changes' => true, 'can_print' => true, 'requires_signature' => true],
                ['name' => 'Finance verification', 'name_sw' => 'Uhakiki wa fedha', 'role' => 'finance', 'assignee_hint' => 'Finance officer',
                    'can_sign' => true, 'can_approve' => true, 'can_reject' => true, 'can_request_changes' => true, 'can_print' => true],
                ['name' => 'Management approval', 'name_sw' => 'Idhini ya menejimenti', 'role' => 'manager', 'assignee_hint' => 'Approving manager',
                    'can_sign' => true, 'can_approve' => true, 'can_reject' => true, 'can_request_changes' => false, 'can_print' => true],
            ],
        ],
        'single' => [
            'name' => 'Single approver',
            'description' => 'Employee → Manager (approve, sign, reject)',
            'steps' => [
                ['name' => 'Request', 'name_sw' => 'Ombi', 'role' => 'employee', 'assignee_hint' => 'Voucher creator',
                    'can_sign' => false, 'can_approve' => false, 'can_reject' => false, 'can_request_changes' => false, 'can_print' => true],
                ['name' => 'Approval', 'name_sw' => 'Idhini', 'role' => 'manager', 'assignee_hint' => 'Approving manager',
                    'can_sign' => true, 'can_approve' => true, 'can_reject' => true, 'can_request_changes' => true, 'can_print' => true],
            ],
        ],
    ];

    public const DEFAULT_VOUCHER_TYPES = [
        ['name' => 'Payment Voucher', 'name_sw' => 'Vocha ya malipo', 'code' => 'payment', 'prefix' => 'PV'],
        ['name' => 'Petty Cash Voucher', 'name_sw' => 'Vocha ya fedha taslimu', 'code' => 'petty_cash', 'prefix' => 'PC'],
        ['name' => 'Expense Voucher', 'name_sw' => 'Vocha ya matumizi', 'code' => 'expense', 'prefix' => 'EX'],
        ['name' => 'Advance Voucher', 'name_sw' => 'Vocha ya malipo ya awali', 'code' => 'advance', 'prefix' => 'AD'],
        ['name' => 'Reimbursement Voucher', 'name_sw' => 'Vocha ya kurejeshewa', 'code' => 'reimbursement', 'prefix' => 'RB'],
        ['name' => 'Other', 'name_sw' => 'Nyingine', 'code' => 'other', 'prefix' => 'OV'],
    ];

    /**
     * @param  array{name:string,email:string,phone?:string,address?:string,website?:string,country?:string,currency?:string,locale?:string}  $companyData
     * @param  array{name:string,email:string,password:string,phone?:string,job_title?:string}  $adminData
     * @return array{company:Company,admin:User}
     */
    public function provision(array $companyData, array $adminData, ?Plan $plan = null): array
    {
        return DB::transaction(function () use ($companyData, $adminData, $plan) {
            $plan ??= Plan::where('is_active', true)->orderBy('sort_order')->first();

            $company = Company::create([
                'name' => $companyData['name'],
                'slug' => $this->uniqueSlug($companyData['name']),
                'legal_name' => $companyData['legal_name'] ?? null,
                'email' => $companyData['email'],
                'phone' => $companyData['phone'] ?? null,
                'address' => $companyData['address'] ?? null,
                'website' => $companyData['website'] ?? null,
                'country' => $companyData['country'] ?? 'TZ',
                'currency' => $companyData['currency'] ?? 'TZS',
                'locale' => $companyData['locale'] ?? 'en',
                'status' => 'trial',
                'voucher_footer_text' => 'This voucher is computer generated and valid without a wet stamp.',
            ]);

            $admin = $this->tenant->forCompany($company, function () use ($company, $adminData) {
                return User::create([
                    'company_id' => $company->id,
                    'name' => $adminData['name'],
                    'email' => $adminData['email'],
                    'password' => $adminData['password'],
                    'phone' => $adminData['phone'] ?? null,
                    'job_title' => $adminData['job_title'] ?? 'Company Administrator',
                    'role' => User::ROLE_COMPANY_ADMIN,
                    'status' => 'active',
                    'locale' => $company->locale,
                    'email_verified_at' => now(),
                ]);
            });

            $this->tenant->forCompany($company, function () use ($company, $admin, $plan) {
                $this->seedVoucherTypes($company);
                $this->applyPreset($company, 'default', $admin);

                if ($plan) {
                    $this->payments->startTrial($company, $plan);
                }
            });

            $this->audit->log(
                'company.created',
                "Created company {$company->name}",
                $company,
                null,
                null,
                $company->id,
            );

            // refresh() so the caller sees the columns the database filled in —
            // the theme default among them — rather than nulls.
            return ['company' => $company->fresh(), 'admin' => $admin->refresh()];
        });
    }

    public function seedVoucherTypes(Company $company): void
    {
        foreach (self::DEFAULT_VOUCHER_TYPES as $index => $type) {
            VoucherType::create([
                'company_id' => $company->id,
                'name' => $type['name'],
                'name_sw' => $type['name_sw'],
                'code' => $type['code'],
                'prefix' => $type['prefix'],
                'next_number' => 1,
                'current_year' => (int) now()->format('Y'),
                'sort_order' => $index,
            ]);
        }
    }

    /** Replaces the tenant's default route with one of the presets. */
    public function applyPreset(Company $company, string $preset, ?User $actor = null): Workflow
    {
        $config = self::PRESETS[$preset] ?? self::PRESETS['default'];

        return DB::transaction(function () use ($company, $config, $actor) {
            Workflow::where('company_id', $company->id)
                ->where('is_default', true)
                ->update(['is_default' => false, 'is_active' => false]);

            $workflow = Workflow::create([
                'company_id' => $company->id,
                'name' => $config['name'],
                'description' => $config['description'],
                'is_default' => true,
                'is_active' => true,
                'created_by' => $actor?->id,
            ]);

            foreach ($config['steps'] as $position => $step) {
                WorkflowStep::create(array_merge([
                    'workflow_id' => $workflow->id,
                    'position' => $position + 1,
                    'can_sign' => false,
                    'can_approve' => false,
                    'can_reject' => false,
                    'can_request_changes' => false,
                    'can_print' => true,
                    'can_download' => true,
                    'requires_signature' => false,
                ], $step));
            }

            return $workflow->load('steps');
        });
    }

    private function uniqueSlug(string $name): string
    {
        $base = Str::slug($name) ?: 'company';
        $slug = $base;
        $suffix = 2;

        while (Company::withTrashed()->where('slug', $slug)->exists()) {
            $slug = $base.'-'.$suffix++;
        }

        return $slug;
    }
}
