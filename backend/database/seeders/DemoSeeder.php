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
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Storage;

/**
 * Demo data across three tenants.
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

            // Demo numbers were handed out from the script, so each tenant's
            // live counters must be moved past them. Without this the first
            // voucher a real user raises would be issued a number that is
            // already on a seeded row.
            foreach ([$primary, $second, $trial] as $company) {
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

    /* ------------------------------------------------------------- factories */

    /** @return array<string,User> */
    private function makePeople(Company $company, array $rows): array
    {
        $people = [];

        foreach ($rows as [$name, $email, $role, $title, $code]) {
            // Approvers keep a saved signature, so the "reuse saved signature"
            // path is exercisable in the demo as well as drawing a fresh one.
            $signs = in_array($role, User::APPROVER_ROLES, true);

            // Email is the account's identity everywhere else in the system;
            // it is the right key here too.
            $people[$name] = User::updateOrCreate(
                ['email' => $email],
                [
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
                ],
            );
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
