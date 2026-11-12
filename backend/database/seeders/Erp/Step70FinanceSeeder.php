<?php

namespace Database\Seeders\Erp;

use App\Models\Company;
use App\Models\Erp\Account;
use App\Models\Erp\Finance\AssetClass;
use App\Models\Erp\Finance\AssetDepreciationRun;
use App\Models\Erp\Finance\BankAccount;
use App\Models\Erp\Finance\BankReconciliation;
use App\Models\Erp\Finance\Budget;
use App\Models\Erp\Finance\CashbookEntry;
use App\Models\Erp\Finance\ClosedPeriod;
use App\Models\Erp\Finance\FixedAsset;
use App\Models\Erp\JournalLine;
use App\Models\Erp\Supplier;
use App\Models\User;
use App\Services\Erp\ChartOfAccounts;
use App\Services\Erp\Finance\AssetClasses;
use App\Services\Erp\Finance\BankAccounts;
use App\Services\Erp\Finance\BankTransfers;
use App\Services\Erp\Finance\Budgets;
use App\Services\Erp\Finance\Cashbook;
use App\Services\Erp\Finance\Depreciation;
use App\Services\Erp\Finance\FiscalYear;
use App\Services\Erp\Finance\FixedAssets;
use App\Services\Erp\Finance\Ledger;
use App\Services\Erp\Finance\PeriodClosing;
use App\Services\Erp\Finance\Reconciliations;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Database\Seeder;

/**
 * Watercom's finance and fixed assets: three bank accounts with opening
 * balances, six months of rent, utilities and other income through the
 * cashbook, float transfers to the M-Pesa till, one completed and one
 * in-progress bank reconciliation, this year's budget, the plant, trucks,
 * computers and furniture with depreciation posted month by month, one
 * disposal, and the older months closed.
 *
 * Idempotent: each part is written only into a company that has none of it.
 */
class Step70FinanceSeeder extends Seeder
{
    private CarbonImmutable $today;

    public function run(): void
    {
        $company = app(TenantContext::class)->company();

        if (! $company) {
            return;
        }

        $this->today = CarbonImmutable::now()->startOfDay();
        $this->enableModules($company);
        app(ChartOfAccounts::class)->seed($company);

        $finance = User::updateOrCreate(['email' => 'daudi@watercom.test'], [
            'company_id' => $company->id, 'name' => 'Daudi Mollel', 'password' => 'Password123!',
            'role' => User::ROLE_FINANCE, 'job_title' => 'Finance Manager', 'employee_code' => 'WC-0175',
            'status' => 'active', 'locale' => 'en', 'email_verified_at' => now(),
        ]);
        $accountant = User::query()->where('email', 'grace@watercom.test')->first() ?? $finance;

        $banks = $this->banks($finance);

        if (! CashbookEntry::query()->exists()) {
            $this->cashbook($banks, $accountant, $finance);
        }

        if (! FixedAsset::query()->exists()) {
            $this->assets($banks, $finance, $accountant);
        }

        if (! BankReconciliation::query()->exists()) {
            $this->reconciliations($banks['nmb'], $accountant);
        }

        if (! Budget::query()->where('fiscal_year', FiscalYear::of($this->today))->exists()) {
            $this->budget($finance);
        }

        if (! ClosedPeriod::query()->exists()) {
            foreach ([6, 5, 4, 3] as $back) {
                app(PeriodClosing::class)->close($this->month($back)->format('Y-m'), $finance);
            }
        }
    }

    private function enableModules(Company $company): void
    {
        $modules = is_array($company->modules) ? $company->modules : [];

        foreach (['accounting', 'assets'] as $module) {
            if (! in_array($module, $modules, true)) {
                $modules[] = $module;
            }
        }

        if ($modules !== $company->modules) {
            $company->forceFill(['modules' => $modules])->save();
        }
    }

    /** @return array<string, BankAccount> */
    private function banks(User $actor): array
    {
        $rows = [
            'nmb' => ['NMB Bank: operations', 'bank', 'NMB Bank', 'Mlimani City', 'Watercom Limited', '2041 0098 3311', 1210, 145_000_000],
            'crdb' => ['CRDB Bank: collections', 'bank', 'CRDB Bank', 'Azikiwe Street', 'Watercom Limited', '0150 4471 9900', 1220, 185_000_000],
            'mpesa' => ['M-Pesa till 556677', 'mobile_money', 'Vodacom M-Pesa', null, 'Watercom Limited', '556677', 1230, 3_200_000],
        ];

        $banks = [];

        foreach ($rows as $key => [$name, $type, $bank, $branch, $holder, $number, $code, $opening]) {
            $banks[$key] = BankAccount::query()->where('account_number', $number)->first()
                ?? app(BankAccounts::class)->create([
                    'name' => $name, 'type' => $type, 'bank_name' => $bank, 'branch' => $branch,
                    'account_name' => $holder, 'account_number' => $number, 'currency' => 'TZS',
                    'code' => Account::query()->where('code', (string) $code)->exists() ? null : $code,
                    'opening_balance' => $opening, 'opening_date' => $this->month(7)->toDateString(),
                ], $actor);
        }

        return $banks;
    }

    /** @param  array<string, BankAccount>  $banks */
    private function cashbook(array $banks, User $preparer, User $finance): void
    {
        $cashbook = app(Cashbook::class);
        $transfers = app(BankTransfers::class);
        $key = fn (string $k) => Account::query()->where('system_key', $k)->value('id');

        $entry = function (string $type, CarbonImmutable $date, BankAccount $bank, string $account, float $amount, string $description, ?string $party = null, ?string $ref = null, bool $post = true) use ($cashbook, $preparer, $finance, $key) {
            $draft = $cashbook->create([
                'type' => $type, 'entry_date' => $date->toDateString(), 'bank_account_id' => $bank->id,
                'account_id' => $key($account), 'amount' => $amount, 'description' => $description,
                'counterparty' => $party, 'reference' => $ref,
            ], $preparer);

            return $post ? $cashbook->post($draft, $finance) : $draft;
        };

        // Owner capital for the new bottling line.
        $entry('receipt', $this->month(6)->addDays(2), $banks['nmb'], 'owner_capital', 50_000_000, 'Capital injection by shareholders', 'Massawe Holdings', 'CAP-01');

        $electric = [3_120_000, 3_350_000, 2_980_000, 3_410_000, 3_270_000, 3_190_000];
        foreach (range(6, 1) as $i => $back) {
            $m = $this->month($back);
            $entry('payment', $m->addDays(4), $banks['nmb'], 'rent', 4_500_000, 'Factory rent, Mbezi Industrial Area', 'Mbezi Properties Ltd', 'RENT-'.$m->format('my'));
            $entry('payment', $m->addDays(11), $banks['crdb'], 'utilities', $electric[$i], 'Electricity, factory meter', 'TANESCO', 'LUKU-'.$m->format('my'));
            $entry('payment', $m->addDays(13), $banks['crdb'], 'utilities', 640_000 + $i * 15_000, 'Water and sewerage', 'DAWASA', 'DAW-'.$m->format('my'));
            $entry('payment', $m->addDays(6), $banks['mpesa'], 'communication_costs', 450_000, 'Fibre internet and phones', 'TTCL', 'TTCL-'.$m->format('my'));
            $entry('receipt', $m->addDays(17), $banks['mpesa'], 'other_income', 1_150_000 + $i * 40_000, 'Sale of scrap PET bales', 'Green Recycling Mwanza', 'SCR-'.$m->format('my'));
            $entry('payment', $m->endOfMonth(), $banks['nmb'], 'bank_charges', 35_000, 'Monthly ledger fee', 'NMB Bank');

            $float = $transfers->create([
                'transfer_date' => $m->addDays(2)->toDateString(), 'from_bank_account_id' => $banks['nmb']->id,
                'to_bank_account_id' => $banks['mpesa']->id, 'amount' => 1_500_000, 'charges' => 2_500, 'reference' => 'FLOAT-'.$m->format('my'),
                'memo' => 'Till float for depot sales',
            ], $preparer);
            $transfers->post($float, $finance);
        }

        $sweep = $transfers->create([
            'transfer_date' => $this->month(2)->addDays(20)->toDateString(), 'from_bank_account_id' => $banks['crdb']->id,
            'to_bank_account_id' => $banks['nmb']->id, 'amount' => 10_000_000, 'charges' => 0, 'reference' => 'SWEEP-01',
            'memo' => 'Collections to operations account',
        ], $preparer);
        $transfers->post($sweep, $finance);

        $entry('payment', $this->month(4)->addDays(9), $banks['crdb'], 'general_insurance', 6_800_000, 'Fire and burglary cover, annual premium', 'Jubilee Insurance', 'POL-77812');
        $entry('payment', $this->month(3)->addDays(15), $banks['nmb'], 'professional_fees', 2_400_000, 'Interim audit fee', 'Mwakyusa & Co. Auditors', 'INV-2241');
        $entry('receipt', $this->month(2)->addDays(8), $banks['nmb'], 'other_income', 900_000, 'Billboard rent, factory wall', 'Kilimanjaro Ads');

        // A cheque written late last month that the bank has not cleared yet.
        $entry('payment', $this->month(1)->addDays(26), $banks['nmb'], 'admin', 1_850_000, 'Pallet racking repairs, cheque 004512', 'Dar Packaging Solutions', 'CHQ-004512');

        // This month, so far: posted, a duplicate reversed, and drafts awaiting approval.
        $day = min(5, $this->today->day);
        $now = $this->today->startOfMonth()->addDays($day - 1);
        $entry('payment', $now, $banks['nmb'], 'rent', 4_500_000, 'Factory rent, Mbezi Industrial Area', 'Mbezi Properties Ltd', 'RENT-'.$now->format('my'));
        $double = $entry('payment', $now, $banks['nmb'], 'rent', 4_500_000, 'Factory rent (keyed twice)', 'Mbezi Properties Ltd', 'RENT-DUP');
        $cashbook->reverse($double, 'Duplicate of the month\'s rent payment', $finance);
        $entry('payment', $this->today, $banks['crdb'], 'utilities', 3_300_000, 'Electricity, factory meter', 'TANESCO', null, false);
        $entry('receipt', $this->today, $banks['mpesa'], 'other_income', 760_000, 'Sale of scrap PET bales', 'Green Recycling Mwanza', null, false);
        $transfers->create([
            'transfer_date' => $this->today->toDateString(), 'from_bank_account_id' => $banks['nmb']->id,
            'to_bank_account_id' => $banks['mpesa']->id, 'amount' => 1_500_000, 'charges' => 2_500, 'memo' => 'Till float for depot sales',
        ], $preparer);
    }

    /** @param  array<string, BankAccount>  $banks */
    private function assets(array $banks, User $finance, User $accountant): void
    {
        app(AssetClasses::class)->ensureDefaults();
        $assets = app(FixedAssets::class);
        $class = fn (string $code) => AssetClass::query()->where('code', $code)->value('id');
        $user = fn (string $email) => User::query()->where('email', $email)->value('id');
        $supplier = Supplier::query()->where('code', 'SUP-0001')->value('id') ?? Supplier::query()->value('id');

        $rows = [
            // tag, name, class, location, custodian, months back, day, cost, residual, funding, bank, serial
            ['WC-PL-001', 'Krones bottling line 6,000 bph', 'PLANT', 'Mbezi factory', 'peter@watercom.test', 7, 3, 480_000_000, 40_000_000, 'opening_equity', null, 'KR-60-22917'],
            ['WC-PL-002', 'Reverse osmosis water plant', 'PLANT', 'Mbezi factory', 'peter@watercom.test', 6, 18, 96_000_000, 6_000_000, 'payable', null, 'RO-5T-0081'],
            ['WC-PL-003', 'Perkins generator 250 kVA', 'PLANT', 'Mbezi factory', 'peter@watercom.test', 5, 9, 85_000_000, 5_000_000, 'bank', 'crdb', 'PK-250-77120'],
            ['WC-MV-001', 'Isuzu FVZ delivery truck T 512 DKL', 'VEH', 'Mbezi factory', 'baraka@watercom.test', 7, 10, 165_000_000, 15_000_000, 'opening_equity', null, 'JALFVZ34P70001234'],
            ['WC-MV-002', 'Isuzu FVZ delivery truck T 774 DKM', 'VEH', 'Arusha depot', 'baraka@watercom.test', 7, 10, 165_000_000, 15_000_000, 'opening_equity', null, 'JALFVZ34P70001899'],
            ['WC-MV-003', 'Toyota Hilux double cabin T 208 DLA', 'VEH', 'Mbezi factory', 'emmanuel@watercom.test', 4, 21, 98_000_000, 10_000_000, 'bank', 'nmb', 'AHTKB8CD702145561'],
            ['WC-IT-001', 'HP ProLiant server', 'COMP', 'Head office, Kijitonyama', 'grace@watercom.test', 6, 12, 14_500_000, 0, 'bank', 'nmb', 'HP-DL380-5521'],
            ['WC-IT-002', 'Dell Latitude laptops (x4)', 'COMP', 'Head office, Kijitonyama', 'grace@watercom.test', 5, 2, 11_200_000, 0, 'bank', 'nmb', null],
            ['WC-IT-003', 'Lenovo ThinkPad (old)', 'COMP', 'Head office, Kijitonyama', 'mwajuma@watercom.test', 7, 6, 3_800_000, 0, 'opening_equity', null, 'LNV-T480-9921'],
            ['WC-FF-001', 'Head office furniture', 'FURN', 'Head office, Kijitonyama', 'admin@watercom.test', 6, 25, 18_600_000, 0, 'bank', 'crdb', null],
            ['WC-FF-002', 'Depot office furniture, Arusha', 'FURN', 'Arusha depot', 'peter@watercom.test', 3, 7, 6_400_000, 0, 'bank', 'mpesa', null],
        ];

        $made = [];
        foreach ($rows as [$tag, $name, $code, $location, $custodian, $back, $day, $cost, $residual, $funding, $bank, $serial]) {
            $made[$tag] = $assets->register([
                'tag' => $tag, 'name' => $name, 'asset_class_id' => $class($code), 'location' => $location,
                'custodian_user_id' => $user($custodian), 'supplier_id' => $funding === 'payable' ? $supplier : null,
                'acquisition_date' => $this->month($back)->addDays($day - 1)->toDateString(),
                'cost' => $cost, 'residual_value' => $residual, 'serial_number' => $serial,
            ], $finance);
            $assets->capitalise($made[$tag], $funding, $bank ? $banks[$bank]->id : null, $finance);
        }

        // Ordered, not yet capitalised: waiting for the supplier's invoice.
        $assets->register([
            'tag' => 'WC-PL-004', 'name' => 'Shrink-wrap packing machine', 'asset_class_id' => $class('PLANT'),
            'location' => 'Mbezi factory', 'custodian_user_id' => $user('peter@watercom.test'), 'supplier_id' => $supplier,
            'acquisition_date' => $this->today->subDays(3)->toDateString(), 'cost' => 37_500_000, 'residual_value' => 2_500_000,
        ], $finance);

        $depreciation = app(Depreciation::class);
        foreach (range(6, 2) as $back) {
            if (! AssetDepreciationRun::query()->where('period', $this->month($back)->format('Y-m'))->exists()) {
                $depreciation->run($this->month($back)->format('Y-m'), $accountant);
            }
        }

        // The old ThinkPad, sold to a member of staff last month.
        $assets->dispose($made['WC-IT-003']->fresh(), [
            'disposal_date' => $this->month(1)->addDays(19)->toDateString(), 'proceeds' => 1_200_000,
            'bank_account_id' => $banks['mpesa']->id, 'reason' => 'Replaced; sold to staff',
        ], $finance);
        $depreciation->run($this->month(1)->format('Y-m'), $accountant);

        // The Hilux moved to the Arusha depot with the sales supervisor.
        $assets->transfer($made['WC-MV-003']->fresh(), [
            'location' => 'Arusha depot', 'custodian_user_id' => $user('hassan@watercom.test') ?? $made['WC-MV-003']->custodian_user_id,
            'date' => $this->month(1)->addDays(2)->toDateString(), 'notes' => 'Depot sales visits in Arusha and Moshi',
        ], $finance);
    }

    /**
     * One completed reconciliation up to the end of two months ago, and one in
     * progress for last month with an outstanding cheque and an unbooked fee.
     */
    private function reconciliations(BankAccount $bank, User $actor): void
    {
        $service = app(Reconciliations::class);
        $ledger = app(Ledger::class);
        $first = $this->month(2)->endOfMonth();
        $second = $this->month(1)->endOfMonth();
        $book = fn (CarbonImmutable $from, CarbonImmutable $to) => JournalLine::query()
            ->where('account_id', $bank->account_id)
            ->whereHas('entry', fn ($q) => $q->whereBetween('entry_date', [$from->toDateString(), $to->toDateString()])->where('id', '!=', $bank->opening_entry_id))
            ->with('entry:id,entry_date,memo')->orderBy('id')->get();
        $asStatement = fn ($line, CarbonImmutable $cap, int $lag = 1) => [
            'line_date' => min($line->entry->entry_date->addDays($lag)->toDateString(), $cap->toDateString()),
            'description' => mb_substr($line->entry->memo, 0, 120),
            'amount' => round((float) $line->debit - (float) $line->credit, 2),
        ];

        $earlier = $book($this->month(12), $first);
        $done = $service->start($bank, [
            'statement_date' => $first->toDateString(),
            'statement_opening_balance' => (float) $bank->opening_balance,
            'statement_closing_balance' => $ledger->balance($bank->account_id, $first->toDateString()),
        ], $actor);
        $service->addLines($done, $earlier->map(fn ($l) => $asStatement($l, $first, 0))->all(), $actor);
        $service->autoMatch($done, $actor);
        $service->complete($done, $actor);

        // Last month: the last payment has not cleared yet, and the bank charged a fee the books lack.
        $lines = $book($this->month(1), $second);
        $outstanding = $lines->first(fn ($l) => str_contains((string) $l->description, 'cheque 004512'));
        $statement = $lines->reject(fn ($l) => $outstanding && $l->is($outstanding))->map(fn ($l) => $asStatement($l, $second))->values()->all();
        $statement[] = ['line_date' => $second->toDateString(), 'description' => 'SMS banking charges', 'amount' => -12_000, 'reference' => 'CHG'];
        $closing = round($ledger->balance($bank->account_id, $first->toDateString()) + array_sum(array_column($statement, 'amount')), 2);

        $open = $service->start($bank, [
            'statement_date' => $second->toDateString(),
            'statement_closing_balance' => $closing,
            'notes' => 'Statement received by email from NMB Mlimani City.',
        ], $actor);
        $service->addLines($open, $statement, $actor);
        $service->autoMatch($open, $actor);
    }

    private function budget(User $actor): void
    {
        $year = FiscalYear::of($this->today);
        $id = fn (string $key) => Account::query()->where('system_key', $key)->value('id');
        $flat = fn (float $amount) => array_fill(0, 12, $amount);
        // Sales climb into the dry season and dip in the long rains (April, May).
        $sales = [210, 205, 215, 180, 175, 195, 220, 235, 240, 245, 250, 260];

        $lines = array_values(array_filter([
            ['account_id' => $id('sales'), 'months' => array_map(fn ($m) => $m * 1_000_000, $sales)],
            ['account_id' => $id('other_income'), 'months' => $flat(1_300_000)],
            ['account_id' => $id('rent'), 'months' => $flat(4_500_000)],
            ['account_id' => $id('utilities'), 'months' => $flat(3_900_000)],
            ['account_id' => $id('communication_costs'), 'months' => $flat(450_000)],
            ['account_id' => $id('bank_charges'), 'months' => $flat(45_000)],
            ['account_id' => $id('depreciation'), 'months' => $flat(18_000_000)],
            ['account_id' => $id('general_insurance'), 'months' => [0, 0, 0, 0, 0, 0, 6_800_000, 0, 0, 0, 0, 0]],
            ['account_id' => $id('professional_fees'), 'months' => [0, 0, 1_200_000, 0, 0, 1_200_000, 0, 0, 2_400_000, 0, 0, 1_200_000]],
            ['account_id' => $id('fuel'), 'months' => $flat(9_500_000)],
            ['account_id' => $id('salaries'), 'months' => $flat(38_000_000)],
        ], fn ($l) => $l['account_id'] !== null));

        app(Budgets::class)->save($year, "Operating budget {$year}", $lines, $actor, 'Approved by the board in January.');
    }

    /** The first day of the month a number of months back. */
    private function month(int $back): CarbonImmutable
    {
        return $this->today->startOfMonth()->subMonthsNoOverflow($back);
    }
}
