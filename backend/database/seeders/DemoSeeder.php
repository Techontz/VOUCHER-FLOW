<?php

namespace Database\Seeders;

use App\Models\Company;
use App\Models\Department;
use App\Models\Plan;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherComment;
use App\Models\VoucherType;
use App\Services\AmountFormatter;
use App\Services\CompanyBranding;
use App\Services\CompanyProvisioner;
use App\Services\PaymentGateway;
use App\Services\VoucherNumberGenerator;
use App\Services\WorkflowEngine;
use App\Support\TenantContext;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Storage;

/**
 * Demo data across four tenants.
 *
 * The second tenant deliberately runs a four-step route with Finance in the
 * middle, so the configurable-workflow behaviour is visible rather than claimed —
 * and so tenant isolation can be checked against a company with different shape.
 *
 * IDEMPOTENT. Running this a second or third time updates the same demo world
 * instead of building another one beside it, because every record it creates is
 * addressed by a stable identity rather than by insertion order:
 *
 *   company      → slug                    (a fixed constant, not a derived one)
 *   user         → email
 *   department   → company_id + name
 *   voucher type → company_id + code
 *   workflow     → company_id + name
 *   voucher      → company_id + number     (the table's own unique key)
 *   comment      → voucher_id + author + body
 *
 * Two consequences worth knowing about:
 *
 *  - Demo voucher numbers are assigned deterministically from the script's own
 *    order, NOT from VoucherNumberGenerator. The generator is a counter, and a
 *    counter cannot produce the same number twice for the same voucher. Each
 *    tenant's counters are then advanced past whatever was seeded, so the first
 *    voucher a real user raises afterwards still gets a free number.
 *
 *  - The historical spread is generated from a fixed random seed, so the demo
 *    world is identical on every environment and a rerun recognises the rows it
 *    wrote last time rather than inventing different ones.
 */
class DemoSeeder extends Seeder
{
    public function __construct(
        private readonly CompanyProvisioner $provisioner,
        private readonly WorkflowEngine $engine,
        private readonly VoucherNumberGenerator $numbers,
        private readonly AmountFormatter $money,
        private readonly PaymentGateway $payments,
        private readonly TenantContext $tenant,
    ) {}

    /**
     * Stable slugs for the demo tenants.
     *
     * CompanyProvisioner derives a slug from the name and appends -2, -3 … to
     * keep it unique, which is right for a real signup and wrong here: it is
     * precisely what let a rerun build a second "Watercom (T) Limited" instead
     * of finding the first. These constants are the demo world's primary keys.
     */
    private const SLUG_PRIMARY = 'watercom';

    private const SLUG_SECOND = 'zamani-logistics';

    private const SLUG_TRIAL = 'baobab-business-solutions';

    private const SLUG_KILIMANJARO = 'kilimanjaro-logistics';

    /**
     * Kilimanjaro draws from its own sequence, re-seeded right before its plan
     * is drawn. The tenants built before it consume a different number of
     * draws on a rerun than on a first run (an existing voucher skips the
     * draws its creation would have made), so sharing the global sequence
     * would hand Kilimanjaro a different plan the second time round.
     */
    private const KILIMANJARO_SEED = 20260927;

    /** Fixed seed for the historical spread, so the demo is reproducible. */
    private const RANDOM_SEED = 20260101;

    public function run(): void
    {
        // Every sample amount, date and payee below comes from this sequence.
        // Seeding it makes the demo world reproducible, which is what lets a
        // rerun match the rows it wrote last time instead of adding new ones.
        mt_srand(self::RANDOM_SEED);

        $this->tenant->withoutScope(function () {
            $business = Plan::where('code', 'business')->first();
            $starter = Plan::where('code', 'starter')->first();
            $enterprise = Plan::where('code', 'enterprise')->first();

            $primary = $this->buildPrimaryTenant($business);
            $second = $this->buildSecondTenant($enterprise);
            $trial = $this->buildTrialTenant($starter);
            $kilimanjaro = $this->buildKilimanjaroTenant($business);

            // Demo numbers were handed out from the script, so each tenant's
            // live counters must be moved past them. Without this the first
            // voucher a real user raises would be issued a number that is
            // already on a seeded row.
            foreach ([$primary, $second, $trial, $kilimanjaro] as $company) {
                $this->syncNumberCounters($company);
            }

            $this->command?->info('Demo tenants ready. Primary company: '.$primary->name);
        });
    }

    /**
     * Moves each voucher type's counter past the highest number already issued
     * for it, so seeded and real vouchers cannot collide.
     */
    private function syncNumberCounters(Company $company): void
    {
        $year = (int) now()->format('Y');

        foreach (VoucherType::withoutGlobalScopes()->where('company_id', $company->id)->get() as $type) {
            $highest = Voucher::withoutGlobalScopes()
                ->where('company_id', $company->id)
                ->where('voucher_type_id', $type->id)
                ->pluck('number')
                ->map(fn (string $number) => (int) preg_replace('/\D/', '', substr($number, strrpos($number, '-') + 1)))
                ->max() ?? 0;

            if ($highest >= (int) $type->next_number) {
                $type->forceFill([
                    'next_number' => $highest + 1,
                    'current_year' => $type->current_year ?: $year,
                ])->save();
            }
        }
    }

    /**
     * Finds this demo tenant, or stands it up if it is not there yet.
     *
     * The `fresh` flag tells the caller whether it is looking at a company that
     * has just been created. Things that must happen exactly once — taking out
     * a subscription, issuing and charging an invoice — are gated on it, since
     * those have no natural unique key to reconcile against.
     *
     * @return array{company:Company,admin:User,fresh:bool}
     */
    private function resolveTenant(string $slug, array $companyData, array $adminData, ?Plan $plan): array
    {
        $existing = Company::withoutGlobalScopes()->where('slug', $slug)->first();

        if ($existing) {
            $admin = User::withoutGlobalScopes()
                ->where('company_id', $existing->id)
                ->where('email', $adminData['email'])
                ->first();

            // A tenant whose administrator was removed still needs one to own
            // the workflow rows and act as the audit actor.
            $admin ??= $this->tenant->forCompany($existing, fn () => User::create([
                'company_id' => $existing->id,
                'name' => $adminData['name'],
                'email' => $adminData['email'],
                'password' => $adminData['password'],
                'job_title' => $adminData['job_title'] ?? 'Company Administrator',
                'role' => User::ROLE_COMPANY_ADMIN,
                'status' => 'active',
                'locale' => $existing->locale,
                'email_verified_at' => now(),
            ]));

            // Cheap to assert, and it repairs a tenant that was seeded before a
            // new default type or a workflow existed. seedVoucherTypes leaves
            // live counters alone.
            $this->tenant->forCompany($existing, function () use ($existing, $admin) {
                $this->provisioner->seedVoucherTypes($existing);

                if (! $existing->workflows()->where('is_default', true)->exists()) {
                    $this->provisioner->applyPreset($existing, 'default', $admin);
                }
            });

            return ['company' => $existing->fresh(), 'admin' => $admin->refresh(), 'fresh' => false];
        }

        ['company' => $company, 'admin' => $admin] = $this->provisioner->provision($companyData, $adminData, $plan);

        // Pin the slug to the constant so the next run finds this row rather
        // than deriving `watercom-t-limited-2` and starting again.
        $company->forceFill(['slug' => $slug])->save();

        return ['company' => $company->fresh(), 'admin' => $admin, 'fresh' => true];
    }

    /* ------------------------------------------------------------ tenant one */

    private function buildPrimaryTenant(?Plan $plan): Company
    {
        ['company' => $company, 'admin' => $admin, 'fresh' => $fresh] = $this->resolveTenant(
            self::SLUG_PRIMARY,
            [
                'name' => 'Watercom (T) Limited',
                'legal_name' => 'WATERCOM (T) LIMITED',
                'email' => 'info@watercom.co.tz',
                'phone' => '+255 22 264 0831',
                'address' => 'P.O. Box 20831, Kibada, Kisarawe II · Dar es Salaam, Tanzania',
                'website' => 'www.watercom.co.tz',
                'currency' => 'TZS',
            ],
            [
                'name' => 'Neema Shirima',
                'email' => 'admin@watercom.test',
                'password' => 'Password123!',
                'job_title' => 'Company Administrator',
            ],
            $plan,
        );

        return $this->tenant->forCompany($company, function () use ($company, $admin, $plan, $fresh) {
            // Demo branding, set through the same columns the Branding screen
            // writes to. Nothing about Watercom is special to the platform —
            // this is one tenant's configuration, not the product's identity.
            $company->forceFill([
                'status' => 'active',
                'trading_name' => 'Watercom',
                'tin' => '109-482-771',
                'registration_number' => '128 471 992',
                'alternative_phone' => '+255 754 640 831',
                'postal_address' => 'P.O. Box 20831, Dar es Salaam',
                'city' => 'Dar es Salaam',
                'region' => 'Kisarawe II, Kibada',
                'contact_person' => 'Neema Shirima',
                'contact_email' => 'info@watercom.co.tz',
                'contact_phone' => '+255 22 264 0831',
                'primary_color' => '#001C94',
                'secondary_color' => '#2E3192',
                'accent_color' => '#22a7e8',
                'bank_name' => 'CRDB Bank',
                'bank_account_name' => 'WATERCOM T LIMITED',
                'bank_account_number' => '0250390569500',
                'bank_branch' => 'Tower Branch',
                'voucher_footer_text' => 'This voucher is computer generated and valid without a wet stamp. Retain the original for audit.',
            ])->save();

            // Artwork goes through the same service an upload uses, so seeded
            // branding and uploaded branding are indistinguishable afterwards —
            // same directory, same random filename, same columns.
            $this->publishBrandAssets($company);

            // Once only. A subscription and its invoices have no natural key to
            // reconcile a rerun against, so re-running this would stack a
            // second paid invoice and a second outstanding one on the billing
            // screen every time.
            if ($plan && $fresh) {
                $subscription = $this->payments->subscribe($company, $plan, 'monthly');
                $invoice = $this->payments->issueInvoice($company, $subscription);
                $this->payments->charge($invoice, ['method' => 'mobile_money', 'reference' => '255222640831']);

                // A second, still-outstanding invoice so the billing screen has both states.
                $this->payments->issueInvoice($company, $subscription, 'Business · monthly (next period)');
            }

            $people = $this->makePeople($company, [
                ['Joseph Mrisho', 'joseph@watercom.test', 'hod', 'Head of Procurement', 'WC-0021'],
                ['Salum Bakari', 'salum@watercom.test', 'hod', 'Transport Manager', 'WC-0044'],
                ['Anna Lyimo', 'anna@watercom.test', 'hod', 'Head of Human Resources', 'WC-0061'],
                ['Rehema Kilonzo', 'rehema@watercom.test', 'hod', 'Head of Finance', 'WC-0032'],
                ['Emmanuel Massawe', 'emmanuel@watercom.test', 'ceo', 'Managing Director', 'WC-0008'],
                ['Mwajuma Hamisi', 'mwajuma@watercom.test', 'cashier', 'Cashier · Finance', 'WC-0056'],
                ['Frank Kessy', 'frank@watercom.test', 'employee', 'Procurement Officer', 'WC-0114'],
                ['Baraka Ndosi', 'baraka@watercom.test', 'employee', 'Transport Supervisor', 'WC-0129'],
                ['Gloria Mtei', 'gloria@watercom.test', 'employee', 'Quality Assurance Officer', 'WC-0141'],
                ['Doreen Massawe', 'doreen@watercom.test', 'employee', 'Human Resources Officer', 'WC-0152'],
            ]);

            // Four heads, each over their own departments, so "an HOD sees only
            // the departments they head" has something real to bite on.
            $departments = $this->makeDepartments($company, [
                ['Procurement', 'PRO', $people['Joseph Mrisho'], $people['Emmanuel Massawe']],
                ['Production', 'PRD', $people['Joseph Mrisho'], $people['Emmanuel Massawe']],
                ['Transport & Logistics', 'TRL', $people['Salum Bakari'], $people['Emmanuel Massawe']],
                ['Sales', 'SLS', $people['Salum Bakari'], $people['Emmanuel Massawe']],
                ['Human Resources', 'HR', $people['Anna Lyimo'], $people['Emmanuel Massawe']],
                ['Finance', 'FIN', $people['Rehema Kilonzo'], $people['Emmanuel Massawe']],
                ['Quality Assurance', 'QA', $people['Rehema Kilonzo'], $people['Emmanuel Massawe']],
            ]);

            $home = [
                'Joseph Mrisho' => 'Procurement',
                'Salum Bakari' => 'Transport & Logistics',
                'Anna Lyimo' => 'Human Resources',
                'Rehema Kilonzo' => 'Finance',
                'Emmanuel Massawe' => 'Finance',
                'Mwajuma Hamisi' => 'Finance',
                'Frank Kessy' => 'Procurement',
                'Baraka Ndosi' => 'Transport & Logistics',
                'Gloria Mtei' => 'Quality Assurance',
                'Doreen Massawe' => 'Human Resources',
            ];

            foreach ($home as $name => $department) {
                $people[$name]->update(['department_id' => $departments[$department]->id]);
            }

            $admin->update(['department_id' => $departments['Human Resources']->id]);

            $this->makeVouchers($company, $people, $departments, $admin);

            return $company->fresh();
        });
    }

    /**
     * Publishes the demo tenant's real artwork.
     *
     * The files under database/seeders/assets are the ACTUAL supplied Watercom
     * lockup, byte for byte, plus a square mark cropped out of it — never a
     * redrawn approximation. They are stored through CompanyBranding so the
     * demo company's logo lives exactly where an uploaded one would, under a
     * per-tenant prefix with a random filename.
     */
    private function publishBrandAssets(Company $company): void
    {
        $branding = app(CompanyBranding::class);

        // Only publish what is not already there. publishFile() writes to a new
        // random filename every time, so re-publishing on each run would orphan
        // the previous file and change the logo's URL — breaking every cached
        // copy of it for no reason.
        $slots = [
            CompanyBranding::SLOT_LOGO => ['logo_path', 'watercom-logo.png'],
            CompanyBranding::SLOT_MARK => ['logo_mark_path', 'watercom-mark.png'],
        ];

        foreach ($slots as $slot => [$column, $file]) {
            $current = $company->{$column};

            if ($current && Storage::disk('public')->exists($current)) {
                continue;
            }

            $branding->publishFile($company, database_path("seeders/assets/{$file}"), $slot);
        }
    }

    /**
     * A tenant on a four-step route. Nothing in the engine changes — only its
     * stored workflow does.
     */
    private function buildSecondTenant(?Plan $plan): Company
    {
        ['company' => $company, 'admin' => $admin, 'fresh' => $fresh] = $this->resolveTenant(
            self::SLUG_SECOND,
            [
                'name' => 'Zamani Logistics',
                'email' => 'finance@zamani-demo.test',
                'phone' => '+255 713 000 202',
                'address' => 'Nyerere Road · Dar es Salaam',
                'currency' => 'TZS',
            ],
            [
                'name' => 'Grace Kimaro',
                'email' => 'admin@zamani.test',
                'password' => 'Password123!',
                'job_title' => 'Group Administrator',
            ],
            $plan,
        );

        return $this->tenant->forCompany($company, function () use ($company, $admin, $plan, $fresh) {
            $company->forceFill(['status' => 'active', 'primary_color' => '#1f6f4a'])->save();

            if ($plan && $fresh) {
                $this->payments->subscribe($company, $plan, 'annual');
            }

            // The distinguishing detail: Finance sits between HOD and Manager.
            // applyPreset retires the current default and writes a new one, so
            // on a rerun it would leave a trail of disabled workflows behind
            // it — apply it once, when the tenant is first stood up.
            if ($fresh) {
                $this->provisioner->applyPreset($company, 'finance', $admin);
            }

            $people = $this->makePeople($company, [
                ['Peter Massawe', 'peter@zamani.test', 'hod', 'Head of Fleet', 'ZL-0011'],
                ['Salma Juma', 'salma@zamani.test', 'finance', 'Finance Controller', 'ZL-0004'],
                ['Erick Mbise', 'erick@zamani.test', 'manager', 'Country Manager', 'ZL-0001'],
                ['Happiness Lyimo', 'happiness@zamani.test', 'employee', 'Fleet Coordinator', 'ZL-0042'],
            ]);

            $departments = $this->makeDepartments($company, [
                ['Fleet', 'FLT', $people['Peter Massawe'], $people['Erick Mbise']],
                ['Finance', 'FIN', $people['Salma Juma'], $people['Erick Mbise']],
            ]);

            $people['Peter Massawe']->update(['department_id' => $departments['Fleet']->id]);
            $people['Happiness Lyimo']->update(['department_id' => $departments['Fleet']->id]);
            $people['Salma Juma']->update(['department_id' => $departments['Finance']->id]);
            $people['Erick Mbise']->update(['department_id' => $departments['Fleet']->id]);

            $type = VoucherType::where('code', 'payment')->first();

            // One voucher that has cleared the HOD and now sits with Finance —
            // step three of four, which the default route does not even have.
            $voucher = $this->makeVoucher($company, [
                'type' => $type,
                'requester' => $people['Happiness Lyimo'],
                'department' => $departments['Fleet'],
                'payee' => 'Kilimanjaro Fuel Supplies',
                'purpose' => 'Diesel for the Arusha convoy',
                'description' => 'Fuel for six trucks on the Arusha run, week 36.',
                'amount' => 12400000,
                'method' => 'Bank Transfer',
                'category' => 'Transport',
                'date' => now()->subDays(2),
            ]);

            $this->submitAs($voucher, $people['Happiness Lyimo']);
            $this->stepThrough($voucher, 'forward', 'Within the fleet budget.');

            return $company->fresh();
        });
    }

    private function buildTrialTenant(?Plan $plan): Company
    {
        ['company' => $company] = $this->resolveTenant(
            self::SLUG_TRIAL,
            [
                'name' => 'Baobab Business Solutions',
                'email' => 'hello@baobab-demo.test',
                'phone' => '+255 714 000 303',
                'currency' => 'TZS',
            ],
            [
                'name' => 'Tumaini Shirima',
                'email' => 'admin@baobab.test',
                'password' => 'Password123!',
                'job_title' => 'Founder',
            ],
            $plan,
        );

        // A trial with three days left, so the expiry banner has something to show.
        $company->forceFill([
            'status' => 'trial',
            'trial_ends_at' => now()->addDays(3),
            'current_period_end' => now()->addDays(3),
        ])->save();

        return $company;
    }

    /* ------------------------------------------------------------ tenant four */

    /**
     * A full-size logistics company on the default route, with nine months of
     * history behind it — enough that dashboards, reports and every queue look
     * like a business that has been running the product for a while.
     *
     * Every voucher is driven through the real WorkflowEngine as the resolved
     * actor, with the clock moved to the moment each action happened, so the
     * approvals, timeline, notifications and audit rows carry coherent dates
     * rather than all stamping "now".
     */
    private function buildKilimanjaroTenant(?Plan $plan): Company
    {
        ['company' => $company, 'admin' => $admin, 'fresh' => $fresh] = $this->resolveTenant(
            self::SLUG_KILIMANJARO,
            [
                'name' => 'Kilimanjaro Logistics Ltd',
                'legal_name' => 'KILIMANJARO LOGISTICS LIMITED',
                'email' => 'info@kilimanjaro.test',
                'phone' => '+255 22 286 4410',
                'address' => 'Plot 14, Mivinjeni Road, Kurasini · Dar es Salaam, Tanzania',
                'currency' => 'TZS',
            ],
            [
                'name' => 'Esther Mbwambo',
                'email' => 'admin@kilimanjaro.test',
                'password' => 'Password123!',
                'job_title' => 'Company Administrator',
                'phone' => '+255 754 210 118',
            ],
            $plan,
        );

        return $this->tenant->forCompany($company, function () use ($company, $admin, $plan, $fresh) {
            $company->forceFill([
                'status' => 'active',
                'trading_name' => 'Kilimanjaro Logistics',
                'tin' => '124-907-352',
                'registration_number' => '152 338 604',
                'alternative_phone' => '+255 767 286 441',
                'postal_address' => 'P.O. Box 45127, Dar es Salaam',
                'city' => 'Dar es Salaam',
                'region' => 'Kurasini, Temeke · Arusha depot, Njiro',
                'timezone' => 'Africa/Dar_es_Salaam',
                'contact_person' => 'Esther Mbwambo',
                'contact_email' => 'info@kilimanjaro.test',
                'contact_phone' => '+255 22 286 4410',
                'bank_name' => 'CRDB Bank',
                'bank_account_name' => 'KILIMANJARO LOGISTICS LIMITED',
                'bank_account_number' => '0150482219700',
                'bank_branch' => 'Azikiwe Branch',
                'voucher_footer_text' => 'This voucher is computer generated and valid without a wet stamp. Retain the original with the EFD receipt for audit.',
            ])->save();

            // Once only, as for Watercom: a subscription and its invoice have
            // no natural key to reconcile a rerun against.
            if ($plan && $fresh) {
                $subscription = $this->payments->subscribe($company, $plan, 'monthly');
                $invoice = $this->payments->issueInvoice($company, $subscription);
                $this->payments->charge($invoice, ['method' => 'mobile_money', 'reference' => '255222864410']);
            }

            // name, email, role, job title, employee code, phone, home department
            $rows = [
                // Heads of department — one each, so every HOD step resolves.
                ['Juma Mwakalinga', 'juma@kilimanjaro.test', 'hod', 'Head of Logistics', 'KL-0012', '+255 754 318 204', 'Logistics'],
                ['Neema Kisanga', 'neema@kilimanjaro.test', 'hod', 'Head of Finance', 'KL-0007', '+255 713 442 918', 'Finance'],
                ['Rehema Nyirenda', 'rehema@kilimanjaro.test', 'hod', 'Head of Human Resources', 'KL-0015', '+255 767 205 731', 'Human Resources'],
                ['Baraka Mushi', 'baraka@kilimanjaro.test', 'hod', 'Head of Operations', 'KL-0010', '+255 755 690 142', 'Operations'],
                ['Elia Massawe', 'elia@kilimanjaro.test', 'hod', 'Head of Procurement', 'KL-0019', '+255 784 117 356', 'Procurement'],
                ['Grace Mollel', 'grace@kilimanjaro.test', 'hod', 'Head of Administration', 'KL-0021', '+255 715 983 420', 'Administration'],
                ['Salim Abdallah', 'salim@kilimanjaro.test', 'hod', 'Head of Sales', 'KL-0024', '+255 658 402 177', 'Sales'],
                ['Upendo Lyimo', 'upendo@kilimanjaro.test', 'hod', 'Head of ICT', 'KL-0028', '+255 746 551 083', 'IT'],
                ['Daudi Kimaro', 'daudi@kilimanjaro.test', 'hod', 'Fleet & Transport Manager', 'KL-0016', '+255 689 274 615', 'Transport'],
                ['Zawadi Temba', 'zawadi@kilimanjaro.test', 'hod', 'Head of Warehousing', 'KL-0031', '+255 762 830 594', 'Warehouse'],

                // Company-wide roles.
                ['Frank Mrema', 'frank@kilimanjaro.test', 'ceo', 'Chief Executive Officer', 'KL-0001', '+255 754 100 227', 'Administration'],
                ['Halima Said', 'halima@kilimanjaro.test', 'cashier', 'Cashier', 'KL-0044', '+255 716 338 902', 'Finance'],
                ['Joseph Shayo', 'joseph@kilimanjaro.test', 'finance', 'Finance Officer', 'KL-0039', '+255 767 419 350', 'Finance'],
                ['Agnes Mwakyusa', 'agnes@kilimanjaro.test', 'manager', 'General Manager, Operations', 'KL-0004', '+255 755 207 846', 'Operations'],

                // Staff who raise the vouchers.
                ['Hamisi Mfinanga', 'hamisi@kilimanjaro.test', 'employee', 'Logistics Coordinator', 'KL-0103', '+255 713 562 019', 'Logistics'],
                ['Irene Swai', 'irene@kilimanjaro.test', 'employee', 'Logistics Officer', 'KL-0118', '+255 784 903 461', 'Logistics'],
                ['Emmanuel Nnko', 'emmanuel@kilimanjaro.test', 'employee', 'Dispatch Officer', 'KL-0126', '+255 767 115 832', 'Logistics'],
                ['Mariam Ally', 'mariam@kilimanjaro.test', 'employee', 'Accounts Assistant', 'KL-0107', '+255 715 280 674', 'Finance'],
                ['Peter Urassa', 'peter@kilimanjaro.test', 'employee', 'Accountant', 'KL-0111', '+255 754 772 305', 'Finance'],
                ['Lucy Minja', 'lucy@kilimanjaro.test', 'employee', 'Human Resources Officer', 'KL-0122', '+255 658 330 917', 'Human Resources'],
                ['Hassan Omary', 'hassan@kilimanjaro.test', 'employee', 'Payroll Officer', 'KL-0129', '+255 746 208 553', 'Human Resources'],
                ['Godfrey Tarimo', 'godfrey@kilimanjaro.test', 'employee', 'Operations Supervisor', 'KL-0114', '+255 689 441 270', 'Operations'],
                ['Anna Shirima', 'anna@kilimanjaro.test', 'employee', 'Operations Officer', 'KL-0133', '+255 762 095 318', 'Operations'],
                ['Yusuph Mkwawa', 'yusuph@kilimanjaro.test', 'employee', 'Site Supervisor – Dodoma yard', 'KL-0141', '+255 713 867 402', 'Operations'],
                ['Faraji Kombo', 'faraji@kilimanjaro.test', 'employee', 'Procurement Officer', 'KL-0120', '+255 784 356 129', 'Procurement'],
                ['Rose Kweka', 'rose@kilimanjaro.test', 'employee', 'Purchasing Assistant', 'KL-0137', '+255 767 612 480', 'Procurement'],
                ['Mwanaisha Juma', 'mwanaisha@kilimanjaro.test', 'employee', 'Office Administrator', 'KL-0109', '+255 715 904 263', 'Administration'],
                ['Fatuma Rashid', 'fatuma@kilimanjaro.test', 'employee', 'Front Office Coordinator', 'KL-0145', '+255 754 486 710', 'Administration'],
                ['Kelvin Makundi', 'kelvin@kilimanjaro.test', 'employee', 'Sales Executive', 'KL-0116', '+255 658 719 034', 'Sales'],
                ['Happiness Mushi', 'happiness@kilimanjaro.test', 'employee', 'Key Account Executive', 'KL-0124', '+255 746 623 591', 'Sales'],
                ['Jacob Laizer', 'jacob@kilimanjaro.test', 'employee', 'Business Development Officer – Arusha', 'KL-0138', '+255 689 205 476', 'Sales'],
                ['Dennis Kavishe', 'dennis@kilimanjaro.test', 'employee', 'Systems Administrator', 'KL-0119', '+255 762 348 105', 'IT'],
                ['Violet Mremi', 'violet@kilimanjaro.test', 'employee', 'IT Support Officer', 'KL-0147', '+255 713 590 826', 'IT'],
                ['Ramadhani Mussa', 'ramadhani@kilimanjaro.test', 'employee', 'Senior Driver', 'KL-0152', '+255 784 061 739', 'Transport'],
                ['Omari Chande', 'omari@kilimanjaro.test', 'employee', 'Fleet Coordinator', 'KL-0113', '+255 767 834 215', 'Transport'],
                ['Musa Kapinga', 'musa@kilimanjaro.test', 'employee', 'Truck Driver', 'KL-0158', '+255 715 147 682', 'Transport'],
                ['Stephen Ngowi', 'stephen@kilimanjaro.test', 'employee', 'Workshop Supervisor', 'KL-0131', '+255 754 928 340', 'Transport'],
                ['Aisha Mohamed', 'aisha@kilimanjaro.test', 'employee', 'Warehouse Supervisor – Kurasini', 'KL-0117', '+255 658 273 916', 'Warehouse'],
                ['Benedict Lema', 'benedict@kilimanjaro.test', 'employee', 'Inventory Controller', 'KL-0125', '+255 746 950 427', 'Warehouse'],
                ['Paulo Mlay', 'paulo@kilimanjaro.test', 'employee', 'Stores Clerk – Arusha depot', 'KL-0149', '+255 689 612 058', 'Warehouse'],
            ];

            $people = $this->makePeople($company, $rows);

            // Every department has its own head; the general manager is the
            // manager of record, so the finance and single presets also resolve
            // if an administrator switches the route over.
            $manager = $people['Agnes Mwakyusa'];
            $departments = $this->makeDepartments($company, [
                ['Logistics', 'LOG', $people['Juma Mwakalinga'], $manager],
                ['Finance', 'FIN', $people['Neema Kisanga'], $manager],
                ['Human Resources', 'HR', $people['Rehema Nyirenda'], $manager],
                ['Operations', 'OPS', $people['Baraka Mushi'], $manager],
                ['Procurement', 'PRC', $people['Elia Massawe'], $manager],
                ['Administration', 'ADM', $people['Grace Mollel'], $manager],
                ['Sales', 'SLS', $people['Salim Abdallah'], $manager],
                ['IT', 'ICT', $people['Upendo Lyimo'], $manager],
                ['Transport', 'TRN', $people['Daudi Kimaro'], $manager],
                ['Warehouse', 'WHS', $people['Zawadi Temba'], $manager],
            ]);

            $staff = [];

            foreach ($rows as [$name, , $role, , , , $home]) {
                $people[$name]->update(['department_id' => $departments[$home]->id]);

                if ($role === User::ROLE_EMPLOYEE) {
                    $staff[$home][] = $people[$name];
                }
            }

            $admin->update([
                'department_id' => $departments['Administration']->id,
                'phone' => '+255 754 210 118',
            ]);

            $this->makeKilimanjaroVouchers($company, $departments, $staff);

            return $company->fresh();
        });
    }

    /**
     * The catalogue Kilimanjaro's vouchers are drawn from.
     *
     * [type code, category, departments (null = any), purpose, payee (null =
     * the requester), min amount, max amount, kind: bank | cash | either]
     *
     * @return list<array{0:string,1:string,2:?array,3:string,4:?string,5:int,6:int,7:string}>
     */
    private function kilimanjaroCatalogue(): array
    {
        return [
            // Fuel
            ['payment', 'Fuel', ['Transport', 'Logistics'], 'Diesel for {route} run, truck {truck}', 'Puma Energy Tanzania', 850000, 3800000, 'bank'],
            ['payment', 'Fuel', ['Transport'], 'Bulk diesel top-up – Kurasini yard tank ({litres} litres)', 'Lake Oil Ltd', 4500000, 12500000, 'bank'],
            ['petty_cash', 'Fuel', ['Operations', 'Sales', 'Administration'], 'Fuel for pool vehicle {car} – {town} errands', 'Oryx Energies – Mikocheni', 60000, 240000, 'cash'],
            ['expense', 'Fuel', ['Transport'], 'Emergency diesel top-up on the road – truck {truck}', 'GBP Tanzania – Chalinze', 180000, 460000, 'cash'],

            // Transport and logistics
            ['expense', 'Transport', ['Logistics', 'Transport'], 'Road tolls and weighbridge fees – {route}', 'TANROADS', 45000, 380000, 'cash'],
            ['petty_cash', 'Transport', ['Administration', 'Finance', 'Human Resources'], 'Bajaji and taxi fares – bank and TRA errands', 'Various transport providers', 35000, 120000, 'cash'],
            ['payment', 'Logistics', ['Logistics'], 'Sub-contracted haulage – {route} consignment', 'Mwanza Cargo Movers Ltd', 2400000, 9800000, 'bank'],
            ['payment', 'Logistics', ['Logistics', 'Warehouse'], 'Port handling and storage charges – container {container}', 'Tanzania Ports Authority', 1200000, 6500000, 'bank'],
            ['payment', 'Logistics', ['Logistics'], 'Clearing and forwarding fees – container {container}', 'Bahari Clearing & Forwarding Ltd', 950000, 4200000, 'bank'],
            ['expense', 'Logistics', ['Logistics'], 'Loading and offloading casual labour – {town} depot', 'Kurasini Casual Labour Group', 120000, 480000, 'cash'],

            // Vehicle maintenance
            ['payment', 'Vehicle maintenance', ['Transport'], 'Tyre replacement for {vehicle}, truck {truck}', 'Kibo Tyres Ltd', 1800000, 7200000, 'bank'],
            ['payment', 'Vehicle maintenance', ['Transport'], 'Scheduled service – {vehicle} {truck}', 'CFAO Motors Tanzania', 950000, 4600000, 'bank'],
            ['expense', 'Vehicle maintenance', ['Transport'], 'Brake pads and clutch kit – truck {truck}', 'Kariakoo Auto Spares', 280000, 1350000, 'either'],
            ['petty_cash', 'Vehicle maintenance', ['Transport'], 'Puncture repair and wheel balancing – truck {truck}', 'Mama Tumaini Tyre Centre', 35000, 180000, 'cash'],

            // Travel and accommodation
            ['advance', 'Travel & accommodation', ['Sales', 'Operations', 'Logistics'], 'Travel advance – {town} client visits ({nights} nights)', null, 450000, 1850000, 'either'],
            ['payment', 'Travel & accommodation', ['Sales', 'Administration'], 'Hotel accommodation – {town} ({nights} nights)', 'Mount Meru Hotel', 380000, 1650000, 'bank'],
            ['reimbursement', 'Travel & accommodation', null, 'Bus fare and lodging refund – {town} trip', null, 85000, 420000, 'cash'],
            ['payment', 'Travel & accommodation', ['Administration'], 'Air tickets Dar es Salaam–Kilimanjaro – management trip', 'Precision Air Services', 780000, 2900000, 'bank'],
            ['advance', 'Travel & accommodation', ['Transport'], 'Driver trip allowance – {route} ({nights} nights)', null, 120000, 480000, 'cash'],

            // Meals and refreshments
            ['petty_cash', 'Meals & refreshments', ['Administration', 'Human Resources'], 'Refreshments for the monthly management meeting', 'Shoppers Supermarket – Masaki', 65000, 280000, 'cash'],
            ['reimbursement', 'Meals & refreshments', ['Sales'], 'Client lunch – {client}', null, 75000, 260000, 'cash'],
            ['expense', 'Meals & refreshments', ['Warehouse', 'Operations'], 'Meals for loading crew – overnight shift', 'Mama Ntilie Catering Services', 90000, 360000, 'cash'],

            // Internet and communications
            ['payment', 'Internet & communications', ['IT'], 'Airtel Business internet bundle – {month}', 'Airtel Tanzania PLC', 480000, 1250000, 'bank'],
            ['payment', 'Internet & communications', ['IT'], 'Fibre link – Kurasini warehouse ({month})', 'TTCL Corporation', 650000, 1450000, 'bank'],
            ['expense', 'Internet & communications', ['IT', 'Sales', 'Operations'], 'Vodacom airtime and data for field staff – {month}', 'Vodacom Tanzania PLC', 150000, 640000, 'either'],
            ['payment', 'Internet & communications', ['IT', 'Transport'], 'GPS fleet tracking subscription – {month}', 'Tracknet Tanzania Ltd', 720000, 1980000, 'bank'],

            // Office supplies and stationery
            ['petty_cash', 'Office supplies & stationery', ['Administration', 'Finance', 'Human Resources'], 'Printing paper, toner and stationery – {month}', 'Kariakoo Stationers', 85000, 460000, 'cash'],
            ['payment', 'Office supplies & stationery', ['Administration', 'Logistics'], 'Pre-printed delivery notes and waybill books', 'Colour Print (T) Ltd', 650000, 2350000, 'bank'],

            // Procurement
            ['payment', 'Procurement', ['Procurement', 'Warehouse'], 'Pallets and stretch film – {town} depot', 'Plasco Limited', 1500000, 6800000, 'bank'],
            ['payment', 'Procurement', ['Procurement'], 'Safety boots and reflector jackets – {qty} pcs', 'Safety Solutions Tanzania', 900000, 3400000, 'bank'],
            ['other', 'Procurement', ['Procurement', 'Operations'], 'Tarpaulins and cargo straps for flatbed trailers', 'Tanzania Tarpaulin Makers', 780000, 2900000, 'bank'],

            // Staff welfare
            ['other', 'Staff welfare', ['Human Resources'], "Drivers' annual medical fitness certificates", 'Regency Medical Centre', 1200000, 4800000, 'bank'],
            ['expense', 'Staff welfare', ['Human Resources'], 'Drinking water and staff tea supply – {month}', 'Kilimanjaro Drinking Water Co.', 120000, 420000, 'cash'],
            ['advance', 'Staff welfare', ['Human Resources', 'Warehouse', 'Transport'], 'Salary advance – approved staff hardship request', null, 250000, 900000, 'either'],
            ['other', 'Staff welfare', ['Human Resources'], 'Condolence contribution – bereaved staff member', 'Staff welfare fund', 150000, 450000, 'cash'],

            // Equipment
            ['payment', 'Equipment', ['IT'], 'Laptops for the dispatch team ({qty} units)', 'Smart Technologies Ltd', 3800000, 11800000, 'bank'],
            ['payment', 'Equipment', ['Warehouse'], 'Hand pallet trucks – Kurasini warehouse', 'Jubilee Machinery Tanzania', 2100000, 6200000, 'bank'],
            ['other', 'Equipment', ['IT'], 'UPS batteries for the server room', 'Serengeti Computer Supplies', 680000, 2150000, 'bank'],

            // Repairs and maintenance
            ['payment', 'Repairs & maintenance', ['Warehouse'], 'Roller door repair – Kurasini warehouse bay {bay}', 'Dar Steel Doors & Fabrication', 650000, 2800000, 'bank'],
            ['expense', 'Repairs & maintenance', ['Administration'], 'Air-conditioner servicing – head office', 'Coolcare Engineering', 240000, 980000, 'either'],
            ['payment', 'Repairs & maintenance', ['Warehouse', 'Operations'], 'Forklift repair – hydraulic pump replacement', 'Toyota Material Handling Tanzania', 1400000, 5600000, 'bank'],
            ['petty_cash', 'Repairs & maintenance', ['Administration', 'Warehouse'], 'Plumbing repairs – {site} washrooms', 'Fundi Petro Plumbing Works', 55000, 220000, 'cash'],

            // Utilities
            ['payment', 'Utilities', ['Warehouse', 'Administration'], 'TANESCO electricity – {site} ({month})', 'TANESCO', 780000, 3600000, 'bank'],
            ['payment', 'Utilities', ['Administration', 'Warehouse'], 'DAWASA water bill – {site} ({month})', 'DAWASA', 120000, 540000, 'bank'],
            ['petty_cash', 'Utilities', ['Administration', 'Warehouse'], 'LUKU prepaid electricity tokens – Arusha depot', 'TANESCO LUKU', 50000, 300000, 'cash'],

            // Professional fees
            ['payment', 'Professional fees', ['Finance'], 'Interim audit fee – {year} financial year', 'Mzizima Audit Partners', 3500000, 9800000, 'bank'],
            ['payment', 'Professional fees', ['Human Resources', 'Administration'], 'Legal review of haulage contracts', 'Makame & Co. Advocates', 1500000, 4800000, 'bank'],
            ['payment', 'Professional fees', ['Logistics', 'Transport'], 'LATRA transport licence renewals – {qty} trucks', 'LATRA', 450000, 2100000, 'bank'],

            // Premises
            ['payment', 'Premises', ['Administration'], 'Office rent – Arusha branch ({month})', 'Njiro Properties Ltd', 2800000, 3800000, 'bank'],
            ['payment', 'Premises', ['Warehouse'], 'Security guarding – Kurasini warehouse ({month})', 'SGA Security Tanzania', 1850000, 3200000, 'bank'],
            ['expense', 'Premises', ['Administration'], 'Office cleaning services – {month}', 'Usafi Bora Cleaning Services', 380000, 850000, 'bank'],

            // Miscellaneous
            ['other', 'Other', ['Finance'], 'Cheque book and bank service charges', 'CRDB Bank PLC', 35000, 180000, 'bank'],
            ['petty_cash', 'Other', ['Sales', 'Operations', 'Logistics'], 'Courier charges – documents to {town}', 'Fargo Courier Services', 35000, 145000, 'cash'],
            ['expense', 'Other', ['Administration'], 'Newspapers, notice boards and office sundries', 'Mwananchi Communications', 40000, 150000, 'cash'],
        ];
    }

    /**
     * Draws the whole demo history for Kilimanjaro, then drives each voucher
     * through the engine in date order so the numbers read chronologically.
     *
     * The plan is drawn in full before anything touches the database, from a
     * sequence seeded here, so it is identical on every run: a rerun addresses
     * the same numbers, finds them, and leaves them exactly as they were.
     *
     * @param  array<string,Department>  $departments
     * @param  array<string,list<User>>  $staff
     */
    private function makeKilimanjaroVouchers(Company $company, array $departments, array $staff): void
    {
        mt_srand(self::KILIMANJARO_SEED);

        $anchor = now()->copy();
        $limit = $anchor->copy()->subMinutes(20);
        $pick = fn (array $list) => $list[mt_rand(0, count($list) - 1)];

        // Target mix: ~57% paid, the rest spread across every queue and outcome.
        $closed = array_merge(
            array_fill(0, 100, 'paid'),
            array_fill(0, 14, 'rejected'),
            array_fill(0, 5, 'cancelled'),
        );
        $open = array_merge(
            array_fill(0, 12, 'approved'),
            array_fill(0, 9, 'awaiting_hod'),
            array_fill(0, 4, 'signed_hold'),
            array_fill(0, 11, 'awaiting_ceo'),
            array_fill(0, 6, 'changes'),
            array_fill(0, 6, 'draft'),
        );

        // Closed vouchers across the last nine months, heavier towards now.
        // Months ago => how many (119 in all, matching $closed).
        $monthOffsets = [];
        foreach ([8 => 8, 7 => 9, 6 => 11, 5 => 12, 4 => 14, 3 => 16, 2 => 19, 1 => 25, 0 => 5] as $monthsAgo => $count) {
            array_push($monthOffsets, ...array_fill(0, $count, $monthsAgo));
        }

        $shuffle = function (array $list): array {
            for ($i = count($list) - 1; $i > 0; $i--) {
                $j = mt_rand(0, $i);
                [$list[$i], $list[$j]] = [$list[$j], $list[$i]];
            }

            return $list;
        };

        $closed = $shuffle($closed);
        $monthOffsets = $shuffle($monthOffsets);

        // Open work is recent — days old, some long enough to count as stalled.
        $openAge = [
            'draft' => [0, 8], 'awaiting_hod' => [0, 7], 'signed_hold' => [0, 5],
            'awaiting_ceo' => [1, 10], 'changes' => [4, 60], 'approved' => [2, 60],
        ];

        // Office hours on the given day, but never later than the present.
        $atWorkTime = function (Carbon $day) use ($limit) {
            $at = $day->copy()->setTime(7, 30)->addMinutes(mt_rand(0, 570));

            return $at->greaterThan($limit) ? $limit->copy()->subMinutes(mt_rand(20, 240)) : $at;
        };

        $dates = [];
        foreach ($closed as $i => $status) {
            $monthsAgo = $monthOffsets[$i];
            $start = $anchor->copy()->startOfMonth()->subMonthsNoOverflow($monthsAgo);
            $span = $monthsAgo === 0 ? max(1, $anchor->day - 7) : $start->daysInMonth;
            $day = $start->copy()->addDays(mt_rand(0, $span - 1));

            if ($day->isSunday()) {
                $day->day === 1 ? $day->addDay() : $day->subDay();
            }

            $dates[] = [$status, $atWorkTime($day)];
        }
        foreach ($open as $status) {
            [$min, $max] = $openAge[$status];
            $dates[] = [$status, $atWorkTime($anchor->copy()->subDays(mt_rand($min, $max)))];
        }

        $catalogue = $this->kilimanjaroCatalogue();
        $deptNames = array_keys($departments);

        $trucks = ['T 482 DKL', 'T 915 DMF', 'T 236 EAB', 'T 710 DHK', 'T 358 DRT', 'T 604 EBC', 'T 127 DXW'];
        $vehicles = ['Scania R460', 'Isuzu FVZ', 'Mitsubishi Fuso FJ', 'Howo 371', 'Mercedes-Benz Actros'];
        $cars = ['T 219 DFP (Toyota Hilux)', 'T 845 DQR (Toyota Prado)', 'T 530 EAK (Suzuki Carry)'];
        $routes = ['Dar es Salaam–Dodoma', 'Arusha–Dodoma', 'Dar es Salaam–Mwanza', 'Tanga–Moshi', 'Dar es Salaam–Mbeya', 'Arusha–Namanga', 'Morogoro–Iringa', 'Dar es Salaam–Arusha'];
        $towns = ['Arusha', 'Dodoma', 'Mwanza', 'Moshi', 'Tanga', 'Mbeya', 'Morogoro', 'Iringa'];
        $clients = ['Bonite Bottlers', 'Kilombero Sugar', 'Arusha Cement Traders', 'Mwanza Fish Processors', 'Tanga Fresh Dairies'];
        $sites = ['Kurasini warehouse', 'Arusha depot', 'Head office, Kurasini', 'Dodoma transit yard'];
        $floats = [
            'Transport' => 'Transport yard float – Kurasini',
            'Warehouse' => 'Warehouse float – Kurasini',
            'Operations' => 'Dodoma yard float',
        ];

        $plan = [];
        foreach ($dates as $index => [$status, $created]) {
            [$typeCode, $category, $depts, $purpose, $payee, $min, $max, $kindRule] = $pick($catalogue);

            $deptName = $pick($depts ?? $deptNames);
            $requester = $pick($staff[$deptName]);

            $raw = mt_rand($min, $max);
            $step = $raw >= 1000000 ? $pick([1000, 5000, 10000, 50000]) : $pick([50, 500, 1000, 5000]);
            $amount = max($min, (int) round($raw / $step) * $step);

            $kind = match ($kindRule) {
                'cash' => Voucher::KIND_CASH,
                'bank' => Voucher::KIND_BANK,
                default => $amount < 500000 && mt_rand(1, 3) > 1 ? Voucher::KIND_CASH : Voucher::KIND_BANK,
            };

            $purpose = strtr($purpose, [
                '{truck}' => $pick($trucks),
                '{vehicle}' => $pick($vehicles),
                '{car}' => $pick($cars),
                '{route}' => $pick($routes),
                '{town}' => $pick($towns),
                '{client}' => $pick($clients),
                '{site}' => $pick($sites),
                '{nights}' => (string) mt_rand(2, 5),
                '{container}' => 'MSKU '.mt_rand(100000, 999999).'-'.mt_rand(0, 9),
                '{litres}' => number_format(mt_rand(20, 60) * 100),
                '{qty}' => (string) mt_rand(4, 24),
                '{bay}' => (string) mt_rand(1, 6),
                '{month}' => $created->format('F'),
                '{year}' => $created->format('Y'),
            ]);

            // Timeline: created ≤ submitted ≤ HOD ≤ CEO ≤ paid, never past now.
            $times = ['created' => $created->copy()];
            $previous = $times['created'];
            foreach (['submitted' => [10, 180], 'hod' => [90, 2880], 'ceo' => [120, 4320], 'paid' => [60, 5760], 'cancelled' => [600, 4320]] as $moment => [$lo, $hi]) {
                $base = $moment === 'cancelled' ? $times['created'] : $previous;
                $at = $base->copy()->addMinutes(mt_rand($lo, $hi));

                // Past the present: land somewhere between the previous step and
                // now rather than on now itself, so recent activity doesn't all
                // share the seeding moment.
                if ($at->greaterThan($limit)) {
                    $room = max(0, (int) $base->diffInMinutes($limit));
                    $at = $base->copy()->addMinutes((int) round($room * mt_rand(35, 90) / 100));
                }
                $times[$moment] = $at->lessThan($base) ? $base->copy() : $at;

                if ($moment !== 'cancelled') {
                    $previous = $times[$moment];
                }
            }

            $plan[] = [
                'index' => $index,
                'status' => $status,
                'type' => $typeCode,
                'category' => $category,
                'department' => $deptName,
                'requester' => $requester,
                'payee' => $payee ?? $requester->name,
                'purpose' => $purpose,
                'amount' => $amount,
                'kind' => $kind,
                'cheque' => $kind === Voucher::KIND_BANK && mt_rand(1, 10) === 1,
                'float' => $floats[$deptName] ?? ($pick([true, false]) ? 'Head office petty cash' : 'Arusha depot float'),
                'ref' => ($kind === Voucher::KIND_CASH ? 'RCPT-' : 'INV-').mt_rand(10000, 99999),
                'times' => $times,
                'changes_at_ceo' => mt_rand(1, 4) === 1,
                'cancel_after_changes' => mt_rand(1, 2) === 1,
                'hod_note' => $pick([
                    'Checked against the department budget line.',
                    'Quotation and delivery note verified.',
                    'Receipts attached and checked.',
                    'Within the approved monthly allocation.',
                    'Confirmed with the requesting supervisor.',
                    'Rate matches the framework agreement.',
                ]),
                'ceo_note' => $pick([
                    'Approved.',
                    'Approved – proceed with payment.',
                    'Cleared for payment.',
                    'Approved. Keep this within the quarterly budget.',
                    'Approved – file the EFD receipt with the voucher.',
                ]),
                'reject_reason' => $pick([
                    'Not budgeted for this quarter – resubmit in the next budget cycle.',
                    'Three quotations are required for purchases above TZS 1,000,000.',
                    'Duplicate of a voucher already paid this month.',
                    'Supplier is not on the approved vendor list – route this through Procurement.',
                    'Amount exceeds the approved per-trip allowance.',
                    'No EFD receipt attached; a fiscal receipt is required for this expense.',
                    'This cost is recoverable from the client under the haulage contract – invoice them instead.',
                ]),
                'changes_reason' => $pick([
                    "Attach the supplier's EFD receipt before this goes up.",
                    'Please attach the signed delivery note from the warehouse.',
                    'Wrong cost centre – this belongs to Transport, not Logistics.',
                    'Amount differs from the quotation. Please correct and resubmit.',
                    'Add the truck registration and trip sheet number to the description.',
                    'Please split fuel and tolls into separate vouchers.',
                ]),
                'cancel_reason' => $pick([
                    'Raised in error – duplicate of an earlier request.',
                    'Supplier withdrew the quotation.',
                    'Trip postponed by the client.',
                ]),
                'remark' => mt_rand(1, 6) === 1 ? $pick([
                    'Quotation attached – the supplier needs payment by Friday.',
                    'EFD receipt uploaded.',
                    'Urgent: the truck is off the road until this is settled.',
                    'Please prioritise; the client is waiting on this delivery.',
                    'Trip sheet attached for reference.',
                ]) : null,
                'cheque_no' => (string) mt_rand(100200, 100990),
                'payment_ref' => (string) mt_rand(1000000, 9999999),
            ];
        }

        // Numbers are handed out in date order, so PV-…-0001 is the oldest.
        usort($plan, fn (array $a, array $b) => [$a['times']['created'], $a['index']] <=> [$b['times']['created'], $b['index']]);

        $types = VoucherType::withoutGlobalScopes()->where('company_id', $company->id)->get()->keyBy('code');

        foreach ($plan as $entry) {
            $this->driveKilimanjaroVoucher($company, $types[$entry['type']], $departments[$entry['department']], $entry);
        }
    }

    /** Raises one planned voucher and walks it to its planned state, on its own clock. */
    private function driveKilimanjaroVoucher(Company $company, VoucherType $type, Department $department, array $e): void
    {
        // Bank => [account prefix, branches]
        $banks = [
            'CRDB Bank' => ['015', ['Azikiwe', 'Kariakoo', 'Mlimani City', 'Arusha']],
            'NMB Bank' => ['201', ['Bank House', 'Kariakoo', 'Arusha Market', 'Dodoma']],
            'NBC Bank' => ['011', ['Corporate', 'Samora Avenue', 'Moshi']],
            'Stanbic Bank' => ['912', ['Kinondoni', 'Industrial Area', 'Arusha']],
            'Exim Bank' => ['020', ['Samora', 'Mwanza', 'Arusha']],
            'Azania Bank' => ['010', ['Head Office', 'Kariakoo', 'Tanga']],
        ];

        // A payee always banks in the same place with the same account.
        $hash = crc32($e['payee']);
        $bankName = array_keys($banks)[$hash % count($banks)];
        [$prefix, $branches] = $banks[$bankName];
        $account = $prefix.sprintf('%010d', $hash);

        $requester = $e['requester'];
        $times = $e['times'];
        $isCash = $e['kind'] === Voucher::KIND_CASH;
        $method = $isCash ? 'Cash' : ($e['cheque'] ? 'Cheque' : 'Bank Transfer');

        // Numbered on the real clock, like every other demo voucher.
        $number = $this->demoNumber($type);

        $restore = Carbon::getTestNow();
        $at = fn (Carbon $moment) => Carbon::setTestNow($moment);

        try {
            $at($times['created']);

            $voucher = $this->makeVoucher($company, [
                'number' => $number,
                'type' => $type,
                'requester' => $requester,
                'department' => $department,
                'kind' => $e['kind'],
                'payee' => $e['payee'],
                'purpose' => $e['purpose'],
                'description' => $e['purpose'].'. Raised by '.$requester->name.' ('.$department->name.').',
                'amount' => $e['amount'],
                'method' => $method,
                'category' => $e['category'],
                'date' => $times['created'],
                'ref' => $e['ref'],
                'payee_bank' => $bankName,
                'payee_account_number' => $account,
                'payee_bank_branch' => $branches[$hash % count($branches)],
                'cash_float' => $e['float'],
            ]);

            if (! $this->isNew($voucher)) {
                return;
            }

            $status = $e['status'];

            if ($status === 'draft') {
                return;
            }

            if ($status === 'cancelled' && ! $e['cancel_after_changes']) {
                $at($times['cancelled']);
                $this->actAs($requester, fn () => $this->engine->cancel($voucher->fresh(), $requester, $e['cancel_reason']));

                return;
            }

            $at($times['submitted']);
            $this->submitAs($voucher, $requester);

            if ($e['remark']) {
                VoucherComment::create([
                    'voucher_id' => $voucher->id, 'company_id' => $company->id,
                    'user_id' => $requester->id, 'body' => $e['remark'],
                ]);
            }

            if ($status === 'awaiting_hod') {
                return;
            }

            $at($times['hod']);

            if ($status === 'signed_hold') {
                $this->stepThrough($voucher, 'hold', $e['hod_note']);

                return;
            }

            if ($status === 'cancelled' || ($status === 'changes' && ! $e['changes_at_ceo'])) {
                $this->stepThrough($voucher, 'changes', $e['changes_reason']);

                if ($status === 'cancelled') {
                    $at($times['ceo']);
                    $this->actAs($requester, fn () => $this->engine->cancel($voucher->fresh(), $requester, $e['cancel_reason']));
                }

                return;
            }

            $this->stepThrough($voucher, 'forward', $e['hod_note']);

            if ($status === 'awaiting_ceo') {
                return;
            }

            $at($times['ceo']);

            match ($status) {
                'changes' => $this->stepThrough($voucher, 'changes', $e['changes_reason']),
                'rejected' => $this->stepThrough($voucher, 'reject', $e['reject_reason']),
                default => $this->stepThrough($voucher, 'approve', $e['ceo_note']),
            };

            if ($status !== 'paid') {
                return;
            }

            $at($times['paid']);
            $this->payAs($voucher, $isCash
                ? ['payment_method' => 'Cash', 'received_by' => $e['payee'], 'payment_reference' => 'PCV-'.$e['payment_ref']]
                : [
                    'payment_method' => $method,
                    'payment_reference' => strtoupper(strtok($bankName, ' ')).'-FT'.$e['payment_ref'],
                    'cheque_number' => $e['cheque'] ? $e['cheque_no'] : null,
                ]);
        } finally {
            Carbon::setTestNow($restore);
        }
    }

    /* ------------------------------------------------------------- factories */

    /** @return array<string,User> */
    private function makePeople(Company $company, array $rows): array
    {
        $people = [];

        foreach ($rows as $row) {
            [$name, $email, $role, $title, $code] = $row;

            // Approvers keep a saved signature, so the "reuse saved signature"
            // path is exercisable in the demo as well as drawing a fresh one.
            $signs = in_array($role, User::APPROVER_ROLES, true);

            // Email is the account's identity everywhere else in the system;
            // it is the right key here too.
            $attributes = [
                'company_id' => $company->id,
                'name' => $name,
                'password' => 'Password123!',
                'role' => $role,
                'job_title' => $title,
                'employee_code' => $code,
                'status' => 'active',
                'locale' => 'en',
                'email_verified_at' => now(),
                'signature_data' => $signs ? $this->sampleSignature() : null,
                'signature_updated_at' => $signs ? now() : null,
            ];

            // An optional sixth column carries a phone number. Only written
            // when given, so rows without one leave the column as it is.
            if (isset($row[5])) {
                $attributes['phone'] = $row[5];
            }

            $people[$name] = User::updateOrCreate(['email' => $email], $attributes);
        }

        return $people;
    }

    /** @return array<string,Department> */
    private function makeDepartments(Company $company, array $rows): array
    {
        $departments = [];

        foreach ($rows as [$name, $code, $hod, $manager]) {
            // departments_company_id_name_unique already says what identifies
            // a department; match it rather than inserting blind.
            $departments[$name] = Department::updateOrCreate(
                [
                    'company_id' => $company->id,
                    'name' => $name,
                ],
                [
                    'code' => $code,
                    'cost_centre' => 'CC-'.$code,
                    'hod_user_id' => $hod?->id,
                    'manager_user_id' => $manager?->id,
                ],
            );
        }

        return $departments;
    }

    /**
     * Per-type sequence for this run, so a given demo voucher always lands on
     * the same number. Keyed by voucher type id.
     *
     * @var array<int,int>
     */
    private array $demoSequence = [];

    /**
     * Ids of the vouchers this run actually inserted.
     *
     * The demo script deliberately parks vouchers mid-flight — one awaiting a
     * signature, one signed but not forwarded, four awaiting approval — and it
     * gets them there by calling the workflow helpers a fixed number of times.
     * Those calls describe a journey from `draft`, so replaying them against a
     * voucher that is already halfway along pushes it FURTHER rather than
     * leaving it be: reruns quietly drained the approval queues to nothing.
     *
     * A voucher that already existed when this run started is history. Nothing
     * below touches it.
     *
     * @var array<int,true>
     */
    private array $createdThisRun = [];

    /**
     * The number a demo voucher should carry.
     *
     * Deliberately NOT VoucherNumberGenerator::next(). That is a counter: it
     * hands out the next unused number and advances, so it cannot produce the
     * same number twice for the same voucher, and a rerun asks it for numbers
     * that are already on disk. This derives the number from the voucher's
     * position in the demo script instead, which is a property of the script
     * and not of the database — the same voucher gets the same number on the
     * first run and the third.
     */
    private function demoNumber(VoucherType $type): string
    {
        $sequence = ($this->demoSequence[$type->id] ?? 0) + 1;
        $this->demoSequence[$type->id] = $sequence;

        return str_replace(
            ['{prefix}', '{year}', '{seq}'],
            [
                $type->prefix,
                now()->format('Y'),
                str_pad((string) $sequence, (int) $type->seq_padding, '0', STR_PAD_LEFT),
            ],
            $type->number_format ?: '{prefix}-{year}-{seq}',
        );
    }

    /**
     * Creates a demo voucher, or returns the one that is already there.
     *
     * firstOrCreate semantics, not updateOrCreate, and the distinction matters:
     * the attributes below describe a voucher at the moment it is raised —
     * status draft, no workflow position. The first run then drove these rows
     * through signing, approval and payment. Writing the draft attributes back
     * over an approved-and-paid voucher would reset it to a draft, and the
     * helpers that follow would drive it again, stacking a second set of
     * approvals, notifications and audit rows behind it. A voucher that has
     * been through the workflow is history, and history is left alone.
     */
    private function makeVoucher(Company $company, array $spec): Voucher
    {
        $type = $spec['type'];
        $currency = $spec['currency'] ?? $company->currency;
        $number = $spec['number'] ?? $this->demoNumber($type);

        $existing = Voucher::withoutGlobalScopes()
            ->where('company_id', $company->id)
            ->where('number', $number)
            ->first();

        if ($existing) {
            return $existing;
        }

        $voucher = Voucher::create([
            'company_id' => $company->id,
            'number' => $number,
            'voucher_type_id' => $type->id,
            'workflow_id' => $this->engine->resolveWorkflow($type)?->id,
            'department_id' => $spec['department']?->id,
            'requester_id' => $spec['requester']->id,
            'payee' => $spec['payee'],
            'purpose' => $spec['purpose'],
            'description' => $spec['description'] ?? null,
            'amount' => $spec['amount'],
            'currency' => $currency,
            'amount_in_words' => $this->money->inWords((float) $spec['amount'], $currency),
            'kind' => $spec['kind'] ?? Voucher::KIND_BANK,
            'payment_method' => $spec['method'] ?? 'Bank Transfer',
            'account_ref' => $spec['ref'] ?? 'INV-'.mt_rand(10000, 99999),

            // Only the particulars the chosen instrument actually uses.
            'payee_bank' => ($spec['kind'] ?? Voucher::KIND_BANK) === Voucher::KIND_BANK ? ($spec['payee_bank'] ?? null) : null,
            'payee_account_name' => ($spec['kind'] ?? Voucher::KIND_BANK) === Voucher::KIND_BANK ? ($spec['payee_account_name'] ?? $spec['payee']) : null,
            'payee_account_number' => ($spec['kind'] ?? Voucher::KIND_BANK) === Voucher::KIND_BANK ? ($spec['payee_account_number'] ?? null) : null,
            'payee_bank_branch' => ($spec['kind'] ?? Voucher::KIND_BANK) === Voucher::KIND_BANK ? ($spec['payee_bank_branch'] ?? null) : null,
            'cash_float' => ($spec['kind'] ?? Voucher::KIND_BANK) === Voucher::KIND_CASH ? ($spec['cash_float'] ?? 'Head office petty cash') : null,
            'category' => $spec['category'] ?? 'Operations',
            'cost_centre' => $spec['department']?->cost_centre,
            'voucher_date' => $spec['date'] ?? now(),
            'status' => Voucher::STATUS_DRAFT,
            'verification_code' => $this->numbers->verificationCode(),
            'created_by' => $spec['requester']->id,
            'updated_by' => $spec['requester']->id,
            'created_at' => $spec['date'] ?? now(),
        ]);

        $this->createdThisRun[$voucher->id] = true;

        return $voucher;
    }

    /** Whether the workflow helpers may act on this voucher at all. */
    private function isNew(Voucher $voucher): bool
    {
        return isset($this->createdThisRun[$voucher->id]);
    }

    /**
     * Builds a spread of vouchers by actually driving them through the engine, so
     * every timeline, notification and audit row is real rather than fabricated.
     */
    private function makeVouchers(Company $company, array $people, array $departments, User $admin): void
    {
        $payment = VoucherType::where('code', 'payment')->first();
        $petty = VoucherType::where('code', 'petty_cash')->first();
        $advance = VoucherType::where('code', 'advance')->first();
        $expense = VoucherType::where('code', 'expense')->first();

        $frank = $people['Frank Kessy'];
        $baraka = $people['Baraka Ndosi'];
        $gloria = $people['Gloria Mtei'];
        $doreen = $people['Doreen Massawe'];
        $joseph = $people['Joseph Mrisho'];

        // 1. Submitted, now awaiting the head of department's signature.
        $awaitingSignature = $this->makeVoucher($company, [
            'type' => $payment, 'requester' => $frank, 'department' => $departments['Procurement'],
            'kind' => Voucher::KIND_BANK,
            'payee' => 'Highland Freight Services', 'purpose' => 'Freight to Mwanza — September consignment',
            'description' => 'Road freight for 22 pallets of Afiya 500ml to the Mwanza depot, per framework contract rate.',
            'amount' => 4850000, 'method' => 'Bank Transfer', 'category' => 'Logistics', 'date' => now()->subDays(2),
            'payee_bank' => 'NMB Bank', 'payee_account_number' => '20110034877', 'payee_bank_branch' => 'Nyerere Road',
        ]);
        $this->submitAs($awaitingSignature, $frank);

        // 2. Signed by the head of department but deliberately not yet submitted
        //    onward — the state the design is specifically built around.
        $signedNotSent = $this->makeVoucher($company, [
            'type' => $payment, 'requester' => $frank, 'department' => $departments['Production'],
            'kind' => Voucher::KIND_BANK,
            'payee' => 'Kibada Preform Suppliers', 'purpose' => 'PET preforms — October production run',
            'description' => 'Two containers of 28mm preforms for the Jembe and Supa Cola lines.',
            'amount' => 21500000, 'method' => 'Bank Transfer', 'category' => 'Raw materials', 'date' => now()->subDays(3),
            'payee_bank' => 'CRDB Bank', 'payee_account_number' => '0150287744100', 'payee_bank_branch' => 'Kariakoo',
        ]);
        $this->submitAs($signedNotSent, $frank);
        $this->stepThrough($signedNotSent, 'hold', 'Within the Q4 raw materials budget. Rate matches the framework contract.');

        // 3. Signed and forwarded — now awaiting the Managing Director's approval.
        $awaitingApproval = $this->makeVoucher($company, [
            'type' => $payment, 'requester' => $baraka, 'department' => $departments['Transport & Logistics'],
            'kind' => Voucher::KIND_BANK,
            'payee' => 'Serengeti Motors Ltd', 'purpose' => 'Fleet servicing — three delivery trucks',
            'description' => 'Scheduled 40,000km service for T-412, T-418 and T-503.',
            'amount' => 7450000, 'method' => 'Bank Transfer', 'category' => 'Fleet', 'date' => now()->subDays(4),
            'payee_bank' => 'NBC Bank', 'payee_account_number' => '011203344556', 'payee_bank_branch' => 'Samora Avenue',
        ]);
        $this->submitAs($awaitingApproval, $baraka);
        $this->stepThrough($awaitingApproval, 'forward', 'Verified against the fleet maintenance schedule.');

        // 4. A cash claim, also awaiting approval — so both formats are in flight.
        $cashAwaiting = $this->makeVoucher($company, [
            'type' => $petty, 'requester' => $gloria, 'department' => $departments['Quality Assurance'],
            'kind' => Voucher::KIND_CASH,
            'payee' => 'Gloria Mtei', 'purpose' => 'Laboratory consumables — reagents',
            'description' => 'Chlorine test reagents and pH buffer solutions bought from the local supplier.',
            'amount' => 385000, 'method' => 'Cash', 'category' => 'Laboratory', 'date' => now()->subDays(3),
            'cash_float' => 'Kibada plant petty cash',
        ]);
        $this->submitAs($cashAwaiting, $gloria);
        $this->stepThrough($cashAwaiting, 'forward', 'Receipts attached and checked.');

        // 5. Approved and waiting on the cashier — the payment queue needs rows.
        $awaitingPayment = $this->makeVoucher($company, [
            'type' => $payment, 'requester' => $frank, 'department' => $departments['Procurement'],
            'kind' => Voucher::KIND_BANK,
            'payee' => 'Coastal Packaging Limited', 'purpose' => 'Shrink film and labels — October',
            'description' => 'Shrink film for the 12-pack line and printed labels for Afiya 1.5L.',
            'amount' => 12400000, 'method' => 'Bank Transfer', 'category' => 'Packaging', 'date' => now()->subDays(6),
            'payee_bank' => 'CRDB Bank', 'payee_account_number' => '0250118877200', 'payee_bank_branch' => 'Mlimani City',
        ]);
        $this->runToCompletion($awaitingPayment, $frank, 'approve', 'Cleared for payment against the October packaging budget.');

        $cashAwaitingPayment = $this->makeVoucher($company, [
            'type' => $advance, 'requester' => $doreen, 'department' => $departments['Human Resources'],
            'kind' => Voucher::KIND_CASH,
            'payee' => 'Doreen Massawe', 'purpose' => 'Staff medical check-up advance',
            'description' => 'Annual food-handler medical certificates for twelve production staff.',
            'amount' => 960000, 'method' => 'Cash', 'category' => 'Staff welfare', 'date' => now()->subDays(5),
            'cash_float' => 'Head office petty cash',
        ]);
        $this->runToCompletion($cashAwaitingPayment, $doreen, 'approve', 'Approved — pay from the head office float.');

        // 6. Paid in full, both formats, so Reports and the payment report have
        //    settled rows and the cashier's "released this month" is not zero.
        $paidBank = $this->makeVoucher($company, [
            'type' => $payment, 'requester' => $frank, 'department' => $departments['Procurement'],
            'kind' => Voucher::KIND_BANK,
            'payee' => 'Tanzania Bottle Company', 'purpose' => 'Glass bottles — September delivery',
            'description' => 'Returnable glass for the Supa Cola 300ml line.',
            'amount' => 18750000, 'method' => 'Bank Transfer', 'category' => 'Raw materials', 'date' => now()->subDays(6),
            'payee_bank' => 'Stanbic Bank', 'payee_account_number' => '9120044556677', 'payee_bank_branch' => 'Kinondoni',
        ]);
        $this->runToCompletion($paidBank, $frank, 'approve', 'Cleared for payment.');
        $this->payAs($paidBank, ['payment_reference' => 'CRDB-TRX-8841207', 'payment_method' => 'Bank Transfer']);

        $paidCash = $this->makeVoucher($company, [
            'type' => $petty, 'requester' => $baraka, 'department' => $departments['Transport & Logistics'],
            'kind' => Voucher::KIND_CASH,
            'payee' => 'Baraka Ndosi', 'purpose' => 'Fuel and tolls — Morogoro run',
            'description' => 'Diesel top-up and road tolls for the Morogoro delivery.',
            'amount' => 420000, 'method' => 'Cash', 'category' => 'Transport', 'date' => now()->subDays(4),
            'cash_float' => 'Transport office float',
        ]);
        $this->runToCompletion($paidCash, $baraka, 'approve', 'Approved against the transport float.');
        $this->payAs($paidCash, ['payment_method' => 'Cash', 'received_by' => 'Baraka Ndosi']);

        // 7. Rejected at the approving step.
        $rejected = $this->makeVoucher($company, [
            'type' => $advance, 'requester' => $baraka, 'department' => $departments['Transport & Logistics'],
            'kind' => Voucher::KIND_CASH,
            'payee' => 'Baraka Ndosi', 'purpose' => 'Travel advance — Dodoma depot visit',
            'description' => 'Three nights, per diem and fuel for the Dodoma inspection.',
            'amount' => 980000, 'method' => 'Cash', 'category' => 'Transport', 'date' => now()->subDays(12),
            'cash_float' => 'Transport office float',
        ]);
        $this->runToCompletion($rejected, $baraka, 'reject', 'Use the depot float for Dodoma travel — resubmit against cost centre CC-TRL.');

        // 8. Returned to the requester for changes at the first approval step.
        $changes = $this->makeVoucher($company, [
            'type' => $expense, 'requester' => $gloria, 'department' => $departments['Quality Assurance'],
            'kind' => Voucher::KIND_BANK,
            'payee' => 'Tanzania Bureau of Standards', 'purpose' => 'Product certification renewal',
            'description' => 'Annual TBS certification for the Afiya and Jembe ranges.',
            'amount' => 2350000, 'method' => 'Bank Transfer', 'category' => 'Compliance', 'date' => now()->subDays(6),
            'payee_bank' => 'CRDB Bank', 'payee_account_number' => '0150900112233', 'payee_bank_branch' => 'Ubungo',
        ]);
        $this->submitAs($changes, $gloria);
        $this->stepThrough($changes, 'changes', 'Attach the TBS invoice and last year’s certificate before this goes up.');

        // 9. A draft — visible to its author and nobody else.
        $this->makeVoucher($company, [
            'type' => $payment, 'requester' => $frank, 'department' => $departments['Procurement'],
            'kind' => Voucher::KIND_BANK,
            'payee' => 'Kibada Preform Suppliers', 'purpose' => 'Caps and closures — November order',
            'description' => 'Draft pending the supplier quotation.',
            'amount' => 4100000, 'method' => 'Bank Transfer', 'category' => 'Raw materials', 'date' => now(),
            'payee_bank' => 'CRDB Bank', 'payee_account_number' => '0150287744100', 'payee_bank_branch' => 'Kariakoo',
        ]);

        // 10. A cash draft, so an employee's queue holds one of each.
        $this->makeVoucher($company, [
            'type' => $petty, 'requester' => $frank, 'department' => $departments['Procurement'],
            'kind' => Voucher::KIND_CASH,
            'payee' => 'Kariakoo Stationers', 'purpose' => 'Office consumables — October',
            'description' => 'Paper, toner and general stationery for the month.',
            'amount' => 310000, 'method' => 'Cash', 'category' => 'Office', 'date' => now(),
            'cash_float' => 'Head office petty cash',
        ]);

        // A little discussion on the record. Author plus wording identifies a
        // seeded remark well enough to recognise it on a rerun; a comment has
        // no other natural key, and two identical remarks by the same person on
        // the same voucher is not something the demo needs to represent.
        VoucherComment::firstOrCreate([
            'voucher_id' => $signedNotSent->id, 'company_id' => $company->id, 'user_id' => $joseph->id,
            'body' => 'Within the Q4 raw materials budget. Rate matches the framework contract.',
        ]);
        VoucherComment::firstOrCreate([
            'voucher_id' => $awaitingApproval->id, 'company_id' => $company->id, 'user_id' => $baraka->id,
            'body' => 'Service history attached — the trucks are due this month.',
        ]);

        // Some history, so the reports and volume chart are not empty.
        $this->makeHistory($company, $payment, $frank, $departments);
    }

    /* ------------------------------------------------------- workflow driving */

    private function submitAs(Voucher $voucher, User $requester): Voucher
    {
        if (! $this->isNew($voucher)) {
            return $voucher->fresh();
        }

        return $this->actAs($requester, fn () => $this->engine->submit($voucher->fresh(), $requester));
    }

    /**
     * Advances the voucher one step, acting as whoever the workflow actually
     * assigns to that step. Because the assignee is resolved rather than assumed,
     * the same helper works for a three-step tenant and a four-step one.
     *
     * @param  string  $decision  forward | approve | reject | changes | hold
     */
    private function stepThrough(Voucher $voucher, string $decision = 'forward', ?string $comment = null): Voucher
    {
        if (! $this->isNew($voucher)) {
            return $voucher->fresh();
        }

        $voucher = $voucher->fresh();
        $step = $this->engine->stepAt($voucher, $voucher->current_step_position);

        if (! $step) {
            return $voucher;
        }

        $actor = $this->engine->assigneesFor($voucher, $step)->first();

        if (! $actor) {
            return $voucher;
        }

        return $this->actAs($actor, function () use ($voucher, $step, $actor, $decision, $comment) {
            if ($decision === 'reject' && $step->can_reject) {
                return $this->engine->reject($voucher, $actor, $comment ?? 'Not approved.');
            }

            if ($decision === 'changes' && $step->can_request_changes) {
                return $this->engine->requestChanges($voucher, $actor, $comment ?? 'Please revise and resubmit.');
            }

            if ($step->can_sign) {
                $this->engine->sign($voucher, $actor, $this->sampleSignature(), $step->can_approve ? null : $comment);
            }

            // "hold" parks the voucher signed-but-not-forwarded.
            if ($decision === 'hold') {
                return $voucher->fresh();
            }

            $fresh = $voucher->fresh();

            return $step->can_approve
                ? $this->engine->approve($fresh, $actor, $comment)
                : $this->engine->submitSigned($fresh, $actor, $comment);
        });
    }

    /**
     * Releases the money, acting as whoever the workflow actually entrusts with
     * it. Resolved rather than assumed, so this works for a tenant that pays
     * from a cashier step and one that pays from finance.
     */
    private function payAs(Voucher $voucher, array $details): Voucher
    {
        if (! $this->isNew($voucher)) {
            return $voucher->fresh();
        }

        $voucher = $voucher->fresh();

        if ($voucher->status !== Voucher::STATUS_APPROVED) {
            return $voucher;
        }

        $step = $this->engine->applicableSteps($voucher)->first(fn ($s) => $s->can_pay);
        $actor = $step ? $this->engine->assigneesFor($voucher, $step)->first() : null;

        if (! $actor) {
            return $voucher;
        }

        return $this->actAs($actor, fn () => $this->engine->pay($voucher, $actor, $details));
    }

    /** Submits, then walks every remaining step until the voucher closes. */
    private function runToCompletion(Voucher $voucher, User $requester, string $finalDecision, ?string $comment = null): Voucher
    {
        $voucher = $this->submitAs($voucher, $requester);

        // Bounded, so a misconfigured workflow cannot spin the seeder forever.
        for ($guard = 0; $guard < 12; $guard++) {
            $voucher = $voucher->fresh();

            if ($voucher->status !== Voucher::STATUS_IN_REVIEW) {
                break;
            }

            $step = $this->engine->stepAt($voucher, $voucher->current_step_position);
            $isFinal = $step && $step->can_approve && ! $this->engine->nextStepAfter($voucher, $step->position);

            $before = [$voucher->status, $voucher->current_step_position];

            $voucher = $this->stepThrough(
                $voucher,
                $isFinal ? $finalDecision : 'forward',
                $isFinal ? $comment : null,
            );

            // A pass that changes nothing will not change anything next time
            // either — on a rerun every step is already recorded, and without
            // this the loop would simply spin to its guard.
            if ([$voucher->status, $voucher->current_step_position] === $before) {
                break;
            }
        }

        return $voucher->fresh();
    }

    private function makeHistory(Company $company, VoucherType $type, User $requester, array $departments): void
    {
        $payees = ['Highland Freight Services', 'Kariakoo Stationers', 'Uhuru Internet Services', 'Coastal Packaging Ltd', 'Serengeti Computer Supplies'];
        $purposes = ['Monthly courier retainer', 'Warehouse cleaning contract', 'Generator servicing', 'Branch water supply', 'Security guarding — monthly'];
        $names = array_keys($departments);

        // mt_rand, not random_int: this sequence is seeded in run(), so the
        // spread is the same on every environment and on every rerun. With a
        // CSPRNG each run invented a different set of history, and the rows
        // written last time could never be recognised again.
        for ($monthsAgo = 6; $monthsAgo >= 1; $monthsAgo--) {
            $count = mt_rand(3, 7);

            for ($i = 0; $i < $count; $i++) {
                $date = now()->subMonthsNoOverflow($monthsAgo)->startOfMonth()->addDays(mt_rand(0, 25));
                $kind = mt_rand(1, 3) === 1 ? Voucher::KIND_CASH : Voucher::KIND_BANK;

                $voucher = $this->makeVoucher($company, [
                    'type' => $type,
                    'requester' => $requester,
                    'department' => $departments[$names[mt_rand(0, count($names) - 1)]],
                    'payee' => $payees[mt_rand(0, count($payees) - 1)],
                    'purpose' => $purposes[mt_rand(0, count($purposes) - 1)],
                    'description' => 'Recurring operational cost, approved against the monthly budget.',
                    'amount' => mt_rand(2, 90) * 100000,
                    'kind' => $kind,
                    'method' => $kind === Voucher::KIND_CASH ? 'Cash' : ['Bank Transfer', 'Mobile Money', 'Cheque'][mt_rand(0, 2)],
                    'category' => ['Logistics', 'Premises', 'Transport', 'Professional fees'][mt_rand(0, 3)],
                    'date' => $date,
                ]);

                // Roughly one in eight is turned down, so the reports have spread.
                $reject = mt_rand(1, 8) === 1;

                $voucher = $this->runToCompletion(
                    $voucher,
                    $requester,
                    $reject ? 'reject' : 'approve',
                    $reject ? 'Outside the approved budget for this period.' : 'Cleared for payment.',
                );

                // Historical vouchers were paid at the time, so the payment
                // report and the cashier's own figures have real depth behind
                // them rather than a queue of six months of unpaid approvals.
                if (! $reject) {
                    $voucher = $this->payAs($voucher, $kind === Voucher::KIND_CASH
                        ? ['payment_method' => 'Cash', 'received_by' => $requester->name]
                        : ['payment_method' => 'Bank Transfer', 'payment_reference' => 'TRX-'.mt_rand(1000000, 9999999)]);
                }

                // Backdate the record so the volume chart spreads across months.
                $voucher->forceFill([
                    'created_at' => $date,
                    'submitted_at' => $date,
                    'approved_at' => $voucher->approved_at ? $date->copy()->addDay() : null,
                    'rejected_at' => $voucher->rejected_at ? $date->copy()->addDay() : null,
                    'paid_at' => $voucher->paid_at ? $date->copy()->addDays(2) : null,
                    'payment_date' => $voucher->paid_at ? $date->copy()->addDays(2)->toDateString() : null,
                ])->save();
            }
        }
    }

    /** Actions are attributed to the acting user, exactly as in the live app. */
    private function actAs(User $user, callable $callback): mixed
    {
        $previous = Auth::user();
        Auth::setUser($user);

        try {
            return $callback();
        } finally {
            $previous ? Auth::setUser($previous) : Auth::forgetUser();
        }
    }

    /** A drawn signature mark, so seeded vouchers and PDFs show a real one. */
    private function sampleSignature(): string
    {
        return 'data:image/png;base64,'
            .'iVBORw0KGgoAAAANSUhEUgAAAQQAAABaCAIAAADRmb9uAAACGElEQVR42u3cSU7DQBBA0boIiPtf0kisESEeumt4X1kiQdr1'
            .'bJPYjkPST2EJJBgkGCQYJBgkGCQYJBgkGCQYJBgkGCQYJBgkGCQYJBgkGCQYJBgkGCQYJBgkGGb09fnx68vKwDB09F++LB0M'
            .'GFABwzwD535eJ7YCDLkY3GXJOp9YOhhq/1uMxI1HYxiqMti4w5t5NIahAINdv4sBGG7YHp34YQBDXgnDSaQ6XYRhP4OxHrK9'
            .'XxiObPM3gUTO9xgk5Jy5rh4yUw8M0k5bs0NE/k+Tg4TkQ9bDQwnYQUL+8Sp9iCj0xwcJdq7+4IkYqp9vVBmvohebBAnOv53U'
            .'DcLQ8mPKhDNX/eOvOPduSeChE4NLGKq81QmXNuwdxE7Xokfj2Rp10dviiWx5l1J0nbCBV0SvGdDGN+tFyzlzb8Dt8zrhNu5o'
            .'Nm1uHPv/+L5cmWlP94gb15qEoiQ8+ukqhmweMFijovESxRNLTEIzGEOWJR5aWadGmohh476ZBGXEsHg0MVBqDMeS70E9ZUg1'
            .'MDy92yZBxTAcCx/ZaxMqO4a/J/iWh7nbeKqE4Tj1lb5PvtUTw1sjzoBGYLhIwqZSNwxvwbB5NAWDBIMEgwSDBIMEgwSD1ByD'
            .'b461twWDtwgDSNoyRd0wQDVwiFNjmLaIXgN3amGH5OUoPejTJMPnPBMGCQYJBgkGCQYJBgkGCQYJBgkGCQYJBgkGaXPfpnAi'
            .'UZSQpmQAAAAASUVORK5CYII=';
    }
}
