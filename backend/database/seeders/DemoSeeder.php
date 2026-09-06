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
use App\Services\CompanyProvisioner;
use App\Services\PaymentGateway;
use App\Services\VoucherNumberGenerator;
use App\Services\WorkflowEngine;
use App\Support\TenantContext;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Auth;

/**
 * Demo data across three tenants.
 *
 * The second tenant deliberately runs a four-step route with Finance in the
 * middle, so the configurable-workflow behaviour is visible rather than claimed —
 * and so tenant isolation can be checked against a company with different shape.
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

    public function run(): void
    {
        $this->tenant->withoutScope(function () {
            $business = Plan::where('code', 'business')->first();
            $starter = Plan::where('code', 'starter')->first();
            $enterprise = Plan::where('code', 'enterprise')->first();

            $acme = $this->buildPrimaryTenant($business);
            $this->buildSecondTenant($enterprise);
            $this->buildTrialTenant($starter);

            $this->command?->info('Demo tenants ready. Primary company: '.$acme->name);
        });
    }

    /* ------------------------------------------------------------ tenant one */

    private function buildPrimaryTenant(?Plan $plan): Company
    {
        ['company' => $company, 'admin' => $admin] = $this->provisioner->provision(
            [
                'name' => 'Acme Tanzania Ltd',
                'email' => 'accounts@acme-demo.test',
                'phone' => '+255 712 000 101',
                'address' => 'Plot 44, Mikocheni · Dar es Salaam',
                'website' => 'https://acme-demo.test',
                'currency' => 'TZS',
            ],
            [
                'name' => 'Neema William',
                'email' => 'admin@acme.test',
                'password' => 'Password123!',
                'job_title' => 'Company Administrator',
            ],
            $plan,
        );

        return $this->tenant->forCompany($company, function () use ($company, $admin, $plan) {
            $company->forceFill([
                'status' => 'active',
                'primary_color' => '#0088b0',
                'voucher_footer_text' => 'This voucher is computer generated and valid without a wet stamp.',
            ])->save();

            if ($plan) {
                $subscription = $this->payments->subscribe($company, $plan, 'monthly');
                $invoice = $this->payments->issueInvoice($company, $subscription);
                $this->payments->charge($invoice, ['method' => 'mobile_money', 'reference' => '255712000101']);

                // A second, still-outstanding invoice so the billing screen has both states.
                $this->payments->issueInvoice($company, $subscription, 'Business · monthly (next period)');
            }

            $people = $this->makePeople($company, [
                ['Asha Mushi', 'asha@acme.test', 'hod', 'Head of Finance', 'AC-0032'],
                ['Peter Sanga', 'peter@acme.test', 'hod', 'Head of Procurement', 'AC-0021'],
                ['Daniel Joseph', 'daniel@acme.test', 'manager', 'Operations Manager', 'AC-0008'],
                ['John Mwakyusa', 'john@acme.test', 'employee', 'Procurement Officer', 'AC-0114'],
                ['Baraka Ndosi', 'baraka@acme.test', 'employee', 'IT Officer', 'AC-0129'],
                ['Fatuma Kalinga', 'fatuma@acme.test', 'finance', 'Finance Officer', 'AC-0056'],
                ['Zawadi Mrema', 'zawadi@acme.test', 'employee', 'Sales Executive', 'AC-0141'],
            ]);

            // Two heads of department, each covering several departments — so the
            // "an HOD sees only the departments they head" rule has something to bite on.
            $departments = $this->makeDepartments($company, [
                ['Finance', 'FIN', $people['Asha Mushi'], $people['Daniel Joseph']],
                ['Operations', 'OPS', $people['Asha Mushi'], $people['Daniel Joseph']],
                ['Human Resources', 'HR', $people['Asha Mushi'], $people['Daniel Joseph']],
                ['Procurement', 'PRO', $people['Peter Sanga'], $people['Daniel Joseph']],
                ['IT', 'IT', $people['Peter Sanga'], $people['Daniel Joseph']],
                ['Sales', 'SLS', $people['Peter Sanga'], $people['Daniel Joseph']],
            ]);

            // Put each person in a department.
            $people['Asha Mushi']->update(['department_id' => $departments['Finance']->id]);
            $people['Peter Sanga']->update(['department_id' => $departments['Procurement']->id]);
            $people['Daniel Joseph']->update(['department_id' => $departments['Operations']->id]);
            $people['John Mwakyusa']->update(['department_id' => $departments['Procurement']->id]);
            $people['Baraka Ndosi']->update(['department_id' => $departments['IT']->id]);
            $people['Fatuma Kalinga']->update(['department_id' => $departments['Finance']->id]);
            $people['Zawadi Mrema']->update(['department_id' => $departments['Sales']->id]);
            $admin->update(['department_id' => $departments['Human Resources']->id]);

            $this->makeVouchers($company, $people, $departments, $admin);

            return $company->fresh();
        });
    }

    /**
     * A tenant on a four-step route. Nothing in the engine changes — only its
     * stored workflow does.
     */
    private function buildSecondTenant(?Plan $plan): Company
    {
        ['company' => $company, 'admin' => $admin] = $this->provisioner->provision(
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

        return $this->tenant->forCompany($company, function () use ($company, $admin, $plan) {
            $company->forceFill(['status' => 'active', 'primary_color' => '#1f6f4a'])->save();

            if ($plan) {
                $this->payments->subscribe($company, $plan, 'annual');
            }

            // The distinguishing detail: Finance sits between HOD and Manager.
            $this->provisioner->applyPreset($company, 'finance', $admin);

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
        ['company' => $company] = $this->provisioner->provision(
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

            $people[$name] = User::create([
                'company_id' => $company->id,
                'name' => $name,
                'email' => $email,
                'password' => 'Password123!',
                'role' => $role,
                'job_title' => $title,
                'employee_code' => $code,
                'status' => 'active',
                'locale' => 'en',
                'email_verified_at' => now(),
                'signature_data' => $signs ? $this->sampleSignature() : null,
                'signature_updated_at' => $signs ? now() : null,
            ]);
        }

        return $people;
    }

    /** @return array<string,Department> */
    private function makeDepartments(Company $company, array $rows): array
    {
        $departments = [];

        foreach ($rows as [$name, $code, $hod, $manager]) {
            $departments[$name] = Department::create([
                'company_id' => $company->id,
                'name' => $name,
                'code' => $code,
                'cost_centre' => 'CC-'.$code,
                'hod_user_id' => $hod?->id,
                'manager_user_id' => $manager?->id,
            ]);
        }

        return $departments;
    }

    private function makeVoucher(Company $company, array $spec): Voucher
    {
        $type = $spec['type'];
        $currency = $spec['currency'] ?? $company->currency;

        return Voucher::create([
            'company_id' => $company->id,
            'number' => $this->numbers->next($type),
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
            'payment_method' => $spec['method'] ?? 'Bank Transfer',
            'account_ref' => $spec['ref'] ?? 'INV-'.random_int(10000, 99999),
            'category' => $spec['category'] ?? 'Operations',
            'cost_centre' => $spec['department']?->cost_centre,
            'voucher_date' => $spec['date'] ?? now(),
            'status' => Voucher::STATUS_DRAFT,
            'verification_code' => $this->numbers->verificationCode(),
            'created_by' => $spec['requester']->id,
            'updated_by' => $spec['requester']->id,
            'created_at' => $spec['date'] ?? now(),
        ]);
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

        $john = $people['John Mwakyusa'];
        $baraka = $people['Baraka Ndosi'];
        $asha = $people['Asha Mushi'];

        // 1. Submitted, now awaiting the head of department's signature.
        $awaitingSignature = $this->makeVoucher($company, [
            'type' => $payment, 'requester' => $john, 'department' => $departments['Procurement'],
            'payee' => 'Highland Freight Services', 'purpose' => 'Freight to Arusha — September consignment',
            'description' => 'Road freight for 14 pallets of stock to the Arusha branch, per framework contract rate.',
            'amount' => 4850000, 'method' => 'Bank Transfer', 'category' => 'Logistics', 'date' => now()->subDays(2),
        ]);
        $this->submitAs($awaitingSignature, $john);

        // 2. Signed by the head of department but deliberately not yet submitted
        //    onward — the state the design is specifically built around.
        $signedNotSent = $this->makeVoucher($company, [
            'type' => $payment, 'requester' => $john, 'department' => $departments['Finance'],
            'payee' => 'Mikocheni Property Holdings', 'purpose' => 'Office rent — Q4 2026',
            'description' => 'Quarterly rent for the Mikocheni head office, per lease clause 4.2.',
            'amount' => 21500000, 'method' => 'Bank Transfer', 'category' => 'Premises', 'date' => now()->subDays(3),
        ]);
        $this->submitAs($signedNotSent, $john);
        $this->stepThrough($signedNotSent, 'hold', 'Within the Q3 budget. Rate matches the framework contract.');

        // 3. Signed and forwarded — now awaiting the manager's approval.
        $awaitingApproval = $this->makeVoucher($company, [
            'type' => $petty, 'requester' => $baraka, 'department' => $departments['IT'],
            'payee' => 'Serengeti Computer Supplies', 'purpose' => 'Replacement laptop batteries',
            'description' => 'Eight replacement batteries for field laptops.',
            'amount' => 1450000, 'method' => 'Mobile Money', 'category' => 'Capital equipment', 'date' => now()->subDays(4),
        ]);
        $this->submitAs($awaitingApproval, $baraka);
        $this->stepThrough($awaitingApproval, 'forward', 'Verified against the IT asset register.');

        // 4. Approved and completed, all the way through.
        $approved = $this->makeVoucher($company, [
            'type' => $petty, 'requester' => $john, 'department' => $departments['Operations'],
            'payee' => 'Kariakoo Stationers', 'purpose' => 'Office consumables — September',
            'description' => 'Paper, toner and general stationery for the month.',
            'amount' => 350000, 'method' => 'Cash', 'category' => 'Staff welfare', 'date' => now()->subDays(9),
        ]);
        $this->runToCompletion($approved, $john, 'approve', 'Cleared for payment.');

        // 5. Rejected at the approving step.
        $rejected = $this->makeVoucher($company, [
            'type' => $advance, 'requester' => $john, 'department' => $departments['Operations'],
            'payee' => 'John Mwakyusa', 'purpose' => 'Travel advance — Mwanza site visit',
            'description' => 'Three nights, per diem and fuel for the Mwanza inspection.',
            'amount' => 980000, 'method' => 'Mobile Money', 'category' => 'Transport', 'date' => now()->subDays(12),
        ]);
        $this->runToCompletion($rejected, $john, 'reject', 'Use the branch float for Mwanza travel — resubmit against cost centre 42.');

        // 6. Returned to the requester for changes at the first approval step.
        $changes = $this->makeVoucher($company, [
            'type' => $expense, 'requester' => $baraka, 'department' => $departments['IT'],
            'payee' => 'Uhuru Internet Services', 'purpose' => 'Branch internet — August arrears',
            'description' => 'Outstanding connectivity charges for the Arusha branch.',
            'amount' => 620000, 'method' => 'Bank Transfer', 'category' => 'Professional fees', 'date' => now()->subDays(6),
        ]);
        $this->submitAs($changes, $baraka);
        $this->stepThrough($changes, 'changes', 'Attach the August invoice and the signed service report.');

        // 7. A draft — visible to its author and nobody else.
        $this->makeVoucher($company, [
            'type' => $payment, 'requester' => $john, 'department' => $departments['Procurement'],
            'payee' => 'Coastal Packaging Ltd', 'purpose' => 'Packaging materials — October order',
            'description' => 'Draft pending the supplier quotation.',
            'amount' => 2750000, 'method' => 'Bank Transfer', 'category' => 'Logistics', 'date' => now(),
        ]);

        // A little discussion on the record.
        VoucherComment::create([
            'voucher_id' => $signedNotSent->id, 'company_id' => $company->id, 'user_id' => $asha->id,
            'body' => 'Within the Q3 logistics budget. Rate matches the framework contract.',
        ]);
        VoucherComment::create([
            'voucher_id' => $awaitingApproval->id, 'company_id' => $company->id, 'user_id' => $baraka->id,
            'body' => 'Quotation attached — the supplier holds this price until the 30th.',
        ]);

        // Some history, so the reports and volume chart are not empty.
        $this->makeHistory($company, $payment, $john, $departments);
    }

    /* ------------------------------------------------------- workflow driving */

    private function submitAs(Voucher $voucher, User $requester): Voucher
    {
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

            $voucher = $this->stepThrough(
                $voucher,
                $isFinal ? $finalDecision : 'forward',
                $isFinal ? $comment : null,
            );
        }

        return $voucher->fresh();
    }

    private function makeHistory(Company $company, VoucherType $type, User $requester, array $departments): void
    {
        $payees = ['Highland Freight Services', 'Kariakoo Stationers', 'Uhuru Internet Services', 'Coastal Packaging Ltd', 'Serengeti Computer Supplies'];
        $purposes = ['Monthly courier retainer', 'Warehouse cleaning contract', 'Generator servicing', 'Branch water supply', 'Security guarding — monthly'];
        $names = array_keys($departments);

        for ($monthsAgo = 6; $monthsAgo >= 1; $monthsAgo--) {
            $count = random_int(3, 7);

            for ($i = 0; $i < $count; $i++) {
                $date = now()->subMonthsNoOverflow($monthsAgo)->startOfMonth()->addDays(random_int(0, 25));

                $voucher = $this->makeVoucher($company, [
                    'type' => $type,
                    'requester' => $requester,
                    'department' => $departments[$names[array_rand($names)]],
                    'payee' => $payees[array_rand($payees)],
                    'purpose' => $purposes[array_rand($purposes)],
                    'description' => 'Recurring operational cost, approved against the monthly budget.',
                    'amount' => random_int(2, 90) * 100000,
                    'method' => ['Bank Transfer', 'Mobile Money', 'Cheque'][random_int(0, 2)],
                    'category' => ['Logistics', 'Premises', 'Transport', 'Professional fees'][random_int(0, 3)],
                    'date' => $date,
                ]);

                // Roughly one in eight is turned down, so the reports have spread.
                $reject = random_int(1, 8) === 1;

                $voucher = $this->runToCompletion(
                    $voucher,
                    $requester,
                    $reject ? 'reject' : 'approve',
                    $reject ? 'Outside the approved budget for this period.' : 'Cleared for payment.',
                );

                // Backdate the record so the volume chart spreads across months.
                $voucher->forceFill([
                    'created_at' => $date,
                    'submitted_at' => $date,
                    'approved_at' => $voucher->approved_at ? $date->copy()->addDay() : null,
                    'rejected_at' => $voucher->rejected_at ? $date->copy()->addDay() : null,
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
