<?php

namespace Database\Seeders\Erp;

use App\Models\Company;
use App\Models\Department;
use App\Models\Erp\Account;
use App\Models\Erp\Hr\Appraisal;
use App\Models\Erp\Hr\AppraisalPeriod;
use App\Models\Erp\Hr\Attendance;
use App\Models\Erp\Hr\Contract;
use App\Models\Erp\Hr\DisciplineCase;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\HrSetting;
use App\Models\Erp\Hr\LeaveRequest;
use App\Models\Erp\Hr\LeaveType;
use App\Models\Erp\Hr\Loan;
use App\Models\Erp\Hr\Movement;
use App\Models\Erp\Hr\OnboardingTask;
use App\Models\Erp\Hr\PayItem;
use App\Models\Erp\Hr\PayrollRun;
use App\Models\Erp\Hr\Separation;
use App\Models\Erp\Hr\Shift;
use App\Models\Erp\Hr\Training;
use App\Models\Erp\Hr\Vacancy;
use App\Models\User;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\Hr\LeaveService;
use App\Services\Erp\Hr\PayrollService;
use App\Services\Erp\Hr\SeparationService;
use App\Services\Erp\Hr\StatutoryRates;
use App\Support\TenantContext;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Watercom's people: an employee record for everyone who signs in plus the
 * factory floor staff who do not, about thirty in all across the departments,
 * with contracts in realistic TZS ranges, a month of attendance, leave in every
 * state, three months of payroll posted and paid, this month's run prepared
 * and waiting for authorisation, a staff loan being recovered, appraisals,
 * training, recruitment, an exit in progress and one open disciplinary case.
 *
 * Re-runnable: people are matched on their employee number, and each kind of
 * history is written only into a company that has none of it yet.
 */
class Step50HrSeeder extends Seeder
{
    /** email => [employee no., title, department, grade, basic, housing, transport, gender, born, hired, bank] */
    private const STAFF = [
        'emmanuel@watercom.test' => ['WC-0008', 'Managing Director', 'Finance', 'M1', 6500000, 1200000, 500000, 'male', '1974-03-18', '2015-01-05', 'CRDB'],
        'admin@watercom.test' => ['WC-0002', 'Company Administrator', 'Human Resources', 'M3', 2600000, 350000, 200000, 'female', '1988-07-02', '2019-04-01', 'NMB'],
        'joseph@watercom.test' => ['WC-0021', 'Head of Procurement', 'Procurement', 'M2', 3400000, 500000, 250000, 'male', '1981-11-23', '2016-08-15', 'NBC'],
        'rehema@watercom.test' => ['WC-0032', 'Head of Finance', 'Finance', 'M2', 3800000, 550000, 250000, 'female', '1983-02-14', '2017-02-01', 'CRDB'],
        'salum@watercom.test' => ['WC-0044', 'Transport Manager', 'Transport & Logistics', 'M3', 2900000, 400000, 250000, 'male', '1980-09-30', '2016-11-07', 'NMB'],
        'mwajuma@watercom.test' => ['WC-0056', 'Cashier', 'Finance', 'S2', 1100000, 150000, 100000, 'female', '1992-05-19', '2020-03-02', 'NMB'],
        'anna@watercom.test' => ['WC-0061', 'Head of Human Resources', 'Human Resources', 'M2', 3200000, 450000, 250000, 'female', '1984-12-08', '2018-01-15', 'Exim'],
        'frank@watercom.test' => ['WC-0114', 'Procurement Officer', 'Procurement', 'S1', 1350000, 180000, 120000, 'male', '1993-04-11', '2021-06-01', 'CRDB'],
        'baraka@watercom.test' => ['WC-0129', 'Transport Supervisor', 'Transport & Logistics', 'S1', 1250000, 150000, 120000, 'male', '1990-01-27', '2021-09-13', 'NBC'],
        'gloria@watercom.test' => ['WC-0141', 'Quality Assurance Officer', 'Quality Assurance', 'S1', 1400000, 180000, 120000, 'female', '1994-06-21', '2022-02-07', 'Stanbic'],
        'doreen@watercom.test' => ['WC-0152', 'Human Resources Officer', 'Human Resources', 'S1', 1300000, 160000, 120000, 'female', '1995-10-03', '2022-07-04', 'NMB'],
        'neema@watercom.test' => ['WC-0170', 'Storekeeper', 'Production', 'S3', 850000, 100000, 80000, 'female', '1996-03-29', '2023-01-09', 'NMB'],
        'peter@watercom.test' => ['WC-0171', 'Warehouse Manager', 'Production', 'M3', 2200000, 300000, 200000, 'male', '1985-08-17', '2019-10-01', 'CRDB'],
        'grace@watercom.test' => ['WC-0172', 'Accountant', 'Finance', 'S1', 1800000, 250000, 150000, 'female', '1989-12-12', '2020-05-18', 'CRDB'],
        'hassan@watercom.test' => ['WC-0173', 'Sales Executive', 'Sales', 'S1', 1500000, 150000, 200000, 'male', '1991-07-07', '2021-03-15', 'NBC'],
        'upendo@watercom.test' => ['WC-0174', 'Procurement Officer', 'Procurement', 'S2', 1200000, 150000, 100000, 'female', '1995-02-25', '2022-10-03', 'NMB'],
        'hr@watercom.test' => ['WC-0180', 'HR & Payroll Manager', 'Human Resources', 'M3', 2700000, 400000, 200000, 'female', '1986-04-04', '2020-08-03', 'CRDB'],
    ];

    /** Floor staff without a sign-in: [no., name, title, department, grade, basic, transport, gender, born, hired, type, phone, city] */
    private const FLOOR = [
        ['WC-0201', 'Juma Mwinyi', 'Machine Operator', 'Production', 'O2', 560000, 60000, 'male', '1993-05-12', '2019-02-04', 'permanent', '0754 221 908', 'Dar es Salaam'],
        ['WC-0202', 'Salma Rashidi', 'Machine Operator', 'Production', 'O2', 540000, 60000, 'female', '1997-09-01', '2021-07-12', 'permanent', '0713 448 201', 'Dar es Salaam'],
        ['WC-0203', 'Elia Mwakalinga', 'Packaging Attendant', 'Production', 'O3', 460000, 50000, 'male', '1999-11-19', '2023-03-06', 'fixed_term', '0688 302 117', 'Dar es Salaam'],
        ['WC-0204', 'Agnes Temba', 'Quality Technician', 'Quality Assurance', 'O1', 780000, 70000, 'female', '1995-01-30', '2020-11-02', 'permanent', '0767 559 044', 'Dar es Salaam'],
        ['WC-0205', 'Musa Kombo', 'Delivery Driver', 'Transport & Logistics', 'O2', 620000, 0, 'male', '1987-06-14', '2018-05-21', 'permanent', '0715 903 662', 'Dar es Salaam'],
        ['WC-0206', 'Halima Abdallah', 'Sales Representative', 'Sales', 'O1', 720000, 120000, 'female', '1994-08-08', '2022-01-17', 'permanent', '0782 114 590', 'Arusha'],
        ['WC-0207', 'Daudi Mapunda', 'Sales Representative', 'Sales', 'O1', 720000, 120000, 'male', '1992-12-02', '2022-04-04', 'fixed_term', '0757 880 213', 'Mwanza'],
        ['WC-0208', 'Zuhura Omari', 'Cleaner', 'Human Resources', 'O4', 350000, 40000, 'female', '1990-03-15', '2021-02-01', 'casual', '0679 220 145', 'Dar es Salaam'],
        ['WC-0209', 'Ibrahim Nyoni', 'Security Guard', 'Transport & Logistics', 'O4', 380000, 40000, 'male', '1985-10-21', '2019-09-09', 'permanent', '0744 671 330', 'Dar es Salaam'],
        ['WC-0210', 'Faraja Lukumay', 'Maintenance Electrician', 'Production', 'O1', 950000, 80000, 'male', '1989-07-25', '2020-06-15', 'permanent', '0762 009 471', 'Dar es Salaam'],
        ['WC-0211', 'Witness Swai', 'Accounts Assistant', 'Finance', 'S3', 880000, 80000, 'female', '1997-04-18', '2023-08-01', 'fixed_term', '0656 338 802', 'Dar es Salaam'],
        ['WC-0212', 'Kelvin Shayo', 'Forklift Operator', 'Production', 'O2', 600000, 60000, 'male', '1996-02-09', '2022-09-05', 'permanent', '0718 772 506', 'Dar es Salaam'],
    ];

    private const BANK_PREFIX = ['CRDB' => '0150', 'NMB' => '2041', 'NBC' => '0110', 'Exim' => '0200', 'Stanbic' => '9120'];

    public function __construct(
        private readonly TenantContext $tenant,
        private readonly LeaveService $leave,
        private readonly PayrollService $payroll,
        private readonly SeparationService $separations,
        private readonly StatutoryRates $rates,
        private readonly DocumentNumberer $numbers,
    ) {}

    public function run(): void
    {
        $company = $this->tenant->company();

        if (! $company) {
            return;
        }

        $this->switchOn($company);

        $hrManager = User::updateOrCreate(['company_id' => $company->id, 'email' => 'hr@watercom.test'], [
            'name' => 'Amina Mfinanga', 'password' => 'Password123!', 'role' => User::ROLE_HR_MANAGER,
            'job_title' => 'HR & Payroll Manager', 'employee_code' => 'WC-0180', 'status' => 'active', 'locale' => 'en',
            'email_verified_at' => now(),
        ]);

        HrSetting::current();
        $this->rates->ensureDefaults('TZ');
        $this->leave->ensureTypes();

        $departments = Department::query()->pluck('id', 'name')->all();
        $shifts = $this->shifts();
        $people = $this->people($company, $departments, $shifts, $hrManager);

        $ceo = User::query()->forTenant($company->id)->where('email', 'emmanuel@watercom.test')->first();
        $accountant = User::query()->forTenant($company->id)->where('email', 'grace@watercom.test')->first();

        $this->movements($people, $departments, $hrManager);
        $this->loansAndItems($people, $hrManager);
        $this->leaveRequests($people, $hrManager);
        $this->attendance($people);
        $this->payrollHistory($hrManager, $ceo, $accountant);
        $this->recruitment($departments, $hrManager);
        $this->performance($people, $hrManager);
        $this->discipline($people, $hrManager);
        $this->exits($people, $hrManager);
    }

    private function switchOn(Company $company): void
    {
        $modules = is_array($company->modules) ? $company->modules : [];

        if (! in_array('hr', $modules, true)) {
            $company->forceFill(['modules' => [...$modules, 'hr']])->save();
        }
    }

    /** @return array<string, Shift> */
    private function shifts(): array
    {
        return [
            'day' => Shift::firstOrCreate(['name' => 'Day shift'], ['start_time' => '08:00', 'end_time' => '17:00', 'grace_minutes' => 10, 'is_default' => true]),
            'early' => Shift::firstOrCreate(['name' => 'Early production'], ['start_time' => '06:00', 'end_time' => '15:00', 'grace_minutes' => 5]),
        ];
    }

    /**
     * Everyone who signs in, with the details above or sensible ones for
     * people added by other modules, and the floor staff.
     *
     * @param  array<string, int>  $departments
     * @param  array<string, Shift>  $shifts
     * @return array<string, Employee> keyed by employee number
     */
    private function people(Company $company, array $departments, array $shifts, User $hrManager): array
    {
        $people = [];
        $users = User::query()->forTenant($company->id)->whereNotIn('role', [User::ROLE_SUPER_ADMIN])->orderBy('id')->get();
        $next = 300;

        foreach ($users as $user) {
            $row = self::STAFF[$user->email] ?? [
                $user->employee_code ?: 'WC-0'.$next++, $user->job_title ?: User::roleLabel($user->role),
                $user->department?->name ?? 'Production', 'S3', 900000, 100000, 80000,
                'male', '1992-01-01', now()->subYears(2)->startOfMonth()->toDateString(), 'NMB',
            ];
            [$number, $title, $department, $grade, $basic, $housing, $transport, $gender, $born, $hired, $bank] = $row;

            $existing = Employee::query()->where('user_id', $user->id)->first();
            if ($existing) {
                $people[$existing->employee_number] = $existing;

                continue;
            }

            while (Employee::query()->where('employee_number', $number)->exists()) {
                $number = 'WC-0'.$next++;
            }

            $employee = $this->employee([
                'user_id' => $user->id, 'employee_number' => $number, 'full_name' => $user->name, 'email' => $user->email,
                'phone' => $user->phone ?: $this->phone($number), 'job_title' => $title, 'grade' => $grade,
                'department_id' => $departments[$department] ?? $user->department_id, 'gender' => $gender,
                'date_of_birth' => $born, 'hire_date' => $hired, 'employment_type' => 'permanent', 'bank_name' => $bank,
                'address' => 'Mbezi Beach, Dar es Salaam',
            ], $basic, $housing, $transport, $hrManager);

            $user->forceFill([
                'department_id' => $user->department_id ?? $employee->department_id,
                'employee_code' => $user->employee_code ?: $employee->employee_number,
            ])->save();
            $people[$employee->employee_number] = $employee;
        }

        foreach (self::FLOOR as [$number, $name, $title, $department, $grade, $basic, $transport, $gender, $born, $hired, $type, $phone, $city]) {
            $existing = Employee::query()->where('employee_number', $number)->first();
            $people[$number] = $existing ?? $this->employee([
                'employee_number' => $number, 'full_name' => $name, 'phone' => $phone, 'job_title' => $title, 'grade' => $grade,
                'department_id' => $departments[$department] ?? null, 'gender' => $gender, 'date_of_birth' => $born,
                'hire_date' => $hired, 'employment_type' => $type, 'bank_name' => $number === 'WC-0208' ? 'NMB' : array_keys(self::BANK_PREFIX)[crc32($number) % 5],
                'address' => $city === 'Dar es Salaam' ? 'Tegeta, Dar es Salaam' : "{$city} town",
                'shift_id' => in_array($department, ['Production'], true) ? $shifts['early']->id : null,
                'heslb_beneficiary' => in_array($number, ['WC-0203', 'WC-0211'], true),
            ], $basic, 0, $transport, $hrManager, $type === 'fixed_term' ? 'fixed_term' : ($type === 'casual' ? 'casual' : 'permanent'));
        }

        // Reporting lines: each department's people report to its head where the head has a record.
        foreach ($people as $employee) {
            if ($employee->manager_id || ! $employee->department_id) {
                continue;
            }
            $headUser = Department::query()->whereKey($employee->department_id)->value('hod_user_id');
            $head = collect($people)->first(fn ($p) => $p->user_id && $p->user_id === (int) $headUser);
            if ($head && $head->id !== $employee->id) {
                $employee->update(['manager_id' => $head->id]);
            }
        }

        // Two recent graduates repay HESLB.
        foreach (['WC-0152', 'WC-0141'] as $number) {
            ($people[$number] ?? null)?->update(['heslb_beneficiary' => true]);
        }

        return $people;
    }

    /** @param  array<string, mixed>  $data */
    private function employee(array $data, float $basic, float $housing, float $transport, User $hrManager, string $contractType = 'permanent'): Employee
    {
        $number = $data['employee_number'];
        $seed = abs(crc32($number));
        $born = Carbon::parse($data['date_of_birth']);
        $bank = $data['bank_name'] ?? 'NMB';

        $employee = Employee::create([
            ...$data,
            'national_id' => sprintf('%s-%05d-%05d-%02d', $born->format('Ymd'), 10000 + $seed % 89999, 10000 + ($seed >> 3) % 89999, $seed % 97),
            'tin' => sprintf('1%02d-%03d-%03d', $seed % 99, ($seed >> 4) % 1000, ($seed >> 8) % 1000),
            'nssf_number' => sprintf('%09d', $seed % 1000000000),
            'bank_account_number' => (self::BANK_PREFIX[$bank] ?? '0100').sprintf('%08d', $seed % 100000000),
            'next_of_kin_name' => $data['gender'] === 'female' ? 'Mussa '.explode(' ', $data['full_name'])[1] : 'Mary '.explode(' ', $data['full_name'])[1],
            'next_of_kin_phone' => $this->phone($number.'k'),
            'next_of_kin_relation' => 'Spouse',
            'probation_end' => Carbon::parse($data['hire_date'])->addMonths(6)->toDateString(),
            'status' => Employee::STATUS_ACTIVE,
            'created_by' => $hrManager->id,
        ]);

        $hired = Carbon::parse($data['hire_date']);
        $raise = now()->startOfYear();

        // Long-serving staff got this year's increment on a new contract; the old one stays on file.
        if ($hired->lt($raise->copy()->subYear())) {
            $employee->contracts()->create([
                'type' => $contractType, 'start_date' => $hired->toDateString(), 'end_date' => $raise->copy()->subDay()->toDateString(),
                'basic_salary' => round($basic / 1.06, -3), 'housing_allowance' => $housing, 'transport_allowance' => $transport,
                'status' => Contract::STATUS_SUPERSEDED, 'created_by' => $hrManager->id,
            ]);
            $start = $raise;
        } else {
            $start = $hired;
        }

        $employee->contracts()->create([
            'type' => $contractType, 'start_date' => $start->toDateString(),
            'end_date' => $contractType === 'fixed_term' ? now()->addDays(20 + $seed % 60)->toDateString() : null,
            'basic_salary' => $basic, 'housing_allowance' => $housing, 'transport_allowance' => $transport,
            'status' => Contract::STATUS_ACTIVE, 'notes' => $start->eq($raise) ? 'Annual increment of 6%' : null, 'created_by' => $hrManager->id,
        ]);

        return $employee;
    }

    /** @param  array<string, Employee>  $people */
    private function movements(array $people, array $departments, User $hrManager): void
    {
        if (Movement::query()->exists()) {
            return;
        }

        if ($baraka = $people['WC-0129'] ?? null) {
            $baraka->movements()->create([
                'type' => 'promotion', 'effective_date' => now()->subMonths(8)->toDateString(),
                'from_department_id' => $baraka->department_id, 'to_department_id' => $baraka->department_id,
                'from_job_title' => 'Senior Driver', 'to_job_title' => 'Transport Supervisor', 'from_grade' => 'O1', 'to_grade' => 'S1',
                'reason' => 'Led the Arusha route without incident for two years', 'created_by' => $hrManager->id,
            ]);
        }

        if (($kelvin = $people['WC-0212'] ?? null) && isset($departments['Transport & Logistics'])) {
            $kelvin->movements()->create([
                'type' => 'transfer', 'effective_date' => now()->subMonths(5)->toDateString(),
                'from_department_id' => $departments['Transport & Logistics'], 'to_department_id' => $kelvin->department_id,
                'from_job_title' => 'Loader', 'to_job_title' => 'Forklift Operator', 'from_grade' => 'O3', 'to_grade' => 'O2',
                'reason' => 'Certified as a forklift operator; moved to the factory store', 'created_by' => $hrManager->id,
            ]);
        }
    }

    /** @param  array<string, Employee>  $people */
    private function loansAndItems(array $people, User $hrManager): void
    {
        if (Loan::query()->exists()) {
            return;
        }

        $firstRun = now()->startOfMonth()->subMonths(3)->format('Y-m');

        if ($juma = $people['WC-0201'] ?? null) {
            Loan::create([
                'employee_id' => $juma->id, 'number' => $this->numbers->next('LOAN'), 'type' => 'loan',
                'principal' => 900000, 'installment' => 150000, 'balance' => 900000, 'start_period' => $firstRun,
                'issued_on' => now()->startOfMonth()->subMonths(3)->toDateString(), 'reason' => 'School fees for two children',
                'status' => Loan::STATUS_ACTIVE, 'created_by' => $hrManager->id,
            ]);
        }

        if ($musa = $people['WC-0205'] ?? null) {
            Loan::create([
                'employee_id' => $musa->id, 'number' => $this->numbers->next('ADV'), 'type' => 'advance',
                'principal' => 200000, 'installment' => 200000, 'balance' => 200000, 'start_period' => now()->format('Y-m'),
                'issued_on' => now()->subDays(6)->toDateString(), 'reason' => 'Medical bill, Amana hospital',
                'status' => Loan::STATUS_ACTIVE, 'created_by' => $hrManager->id,
            ]);
        }

        foreach (['WC-0201', 'WC-0202', 'WC-0203', 'WC-0212', 'WC-0210'] as $number) {
            if ($e = $people[$number] ?? null) {
                PayItem::create([
                    'employee_id' => $e->id, 'kind' => 'deduction', 'category' => 'union', 'description' => 'TUICO union dues',
                    'amount' => 5000, 'start_period' => $firstRun, 'created_by' => $hrManager->id,
                ]);
            }
        }

        if ($agnes = $people['WC-0204'] ?? null) {
            $period = now()->startOfMonth()->subMonth()->format('Y-m');
            PayItem::create([
                'employee_id' => $agnes->id, 'kind' => 'earning', 'category' => 'arrears', 'description' => 'Grade arrears, July to September',
                'amount' => 135000, 'start_period' => $period, 'end_period' => $period, 'created_by' => $hrManager->id,
            ]);
        }

        if ($hassan = collect($people)->first(fn ($p) => $p->email === 'hassan@watercom.test')) {
            PayItem::create([
                'employee_id' => $hassan->id, 'kind' => 'earning', 'category' => 'commission', 'description' => 'Sales commission',
                'amount' => 250000, 'start_period' => now()->format('Y-m'), 'end_period' => now()->format('Y-m'), 'created_by' => $hrManager->id,
            ]);
        }
    }

    /** @param  array<string, Employee>  $people */
    private function leaveRequests(array $people, User $hrManager): void
    {
        if (LeaveRequest::query()->exists()) {
            return;
        }

        $type = fn (string $code) => LeaveType::query()->where('code', $code)->value('id');
        $weekday = function (Carbon $d): Carbon {
            while ($d->isWeekend()) {
                $d->addDay();
            }

            return $d;
        };

        // [employee no., type, start, end, final status, reason]
        $plan = [
            ['WC-0204', 'annual', $weekday(now()->subDays(24)), null, 'approved', 'Family visit in Moshi', 5],
            ['WC-0210', 'annual', $weekday(now()->subDay()), null, 'approved', 'Annual leave', 6],
            ['WC-0202', 'sick', $weekday(now()->subDays(8)), null, 'approved', 'Malaria, doctor\'s note attached', 2],
            ['WC-0207', 'unpaid', $weekday(now()->startOfMonth()->subMonth()->addDays(9)), null, 'approved', 'Personal matters in Mwanza', 1],
            ['WC-0141', 'annual', $weekday(now()->addDays(18)), null, 'pending', 'End of year break', 5],
            ['WC-0212', 'paternity', $weekday(now()->addDays(4)), null, 'pending', 'Wife due this week', 3],
            ['WC-0129', 'annual', $weekday(now()->addDays(9)), null, 'pending', 'Wedding in Arusha', 4],
            ['WC-0203', 'annual', $weekday(now()->addDays(2)), null, 'rejected', 'Short break', 3],
            ['WC-0114', 'compassionate', $weekday(now()->addDays(12)), null, 'cancelled', 'Funeral, later postponed', 2],
        ];

        foreach ($plan as [$number, $code, $start, $end, $status, $reason, $days]) {
            $employee = $people[$number] ?? null;
            if (! $employee) {
                continue;
            }

            $end = $start->copy();
            for ($counted = 1; $counted < $days; $end->addDay()) {
                if (! $end->copy()->addDay()->isWeekend()) {
                    $counted++;
                }
            }

            try {
                $request = $this->leave->request($employee, [
                    'leave_type_id' => $type($code), 'start_date' => $start->toDateString(), 'end_date' => $end->toDateString(), 'reason' => $reason,
                ], $employee->user ?? $hrManager);

                match ($status) {
                    'approved' => $this->leave->approve($request, $hrManager, 'Enjoy your leave'),
                    'rejected' => $this->leave->reject($request, $hrManager, 'Line changeover that week; please choose other dates'),
                    'cancelled' => $this->leave->cancel($request, $hrManager),
                    default => null,
                };
            } catch (RuntimeException $e) {
                $this->command?->warn("HR demo: leave for {$number} skipped: {$e->getMessage()}");
            }
        }
    }

    /**
     * The last month, weekday by weekday: most people on time, some late,
     * the odd absence, overtime on the production line, and leave where it
     * was approved. Today has check-ins only.
     *
     * @param  array<string, Employee>  $people
     */
    private function attendance(array $people): void
    {
        if (Attendance::query()->exists()) {
            return;
        }

        $leave = LeaveRequest::query()->where('status', LeaveRequest::STATUS_APPROVED)->get();
        $rows = [];
        $companyId = $this->tenant->id();

        for ($day = now()->subDays(30)->startOfDay(); $day->lte(today()); $day->addDay()) {
            if ($day->isWeekend()) {
                continue;
            }

            foreach ($people as $employee) {
                if ($employee->hire_date->gt($day) || $employee->status !== Employee::STATUS_ACTIVE) {
                    continue;
                }

                $onLeave = $leave->first(fn ($r) => $r->employee_id === $employee->id && $day->between($r->start_date, $r->end_date));
                $roll = abs(crc32($employee->employee_number.$day->toDateString())) % 100;
                $early = $employee->shift_id && $employee->department?->name === 'Production';
                $startHour = $early ? 6 : 8;
                $today = $day->isToday();

                if ($onLeave) {
                    $status = 'leave';
                } elseif ($roll < 3 && ! $today) {
                    $status = 'absent';
                } elseif ($roll < 12) {
                    $status = 'late';
                } else {
                    $status = 'present';
                }

                $in = $out = null;
                $hours = $overtime = 0;

                if (in_array($status, ['present', 'late'], true)) {
                    $minute = $status === 'late' ? 15 + $roll * 3 % 50 : ($roll * 7) % 20 - 10;
                    $in = Carbon::parse($day->toDateString())->setTime($startHour, 0)->addMinutes($minute);
                    if (! $today) {
                        $extra = $early && $roll > 80 ? 120 : ($roll % 4) * 10;
                        $out = Carbon::parse($day->toDateString())->setTime($startHour + 9, 0)->addMinutes($extra);
                        $hours = round($in->diffInMinutes($out) / 60, 2);
                        $overtime = round(max(0, $hours - 9), 2);
                    }
                }

                $rows[] = [
                    'company_id' => $companyId, 'employee_id' => $employee->id, 'date' => $day->toDateString(),
                    'check_in' => $in?->format('H:i:s'), 'check_out' => $out?->format('H:i:s'), 'status' => $status,
                    'hours_worked' => $hours, 'overtime_hours' => $overtime, 'source' => $roll % 5 === 0 ? 'manual' : 'import',
                    'note' => $onLeave ? 'On approved leave' : null, 'created_at' => now(), 'updated_at' => now(),
                ];
            }
        }

        foreach (array_chunk($rows, 300) as $chunk) {
            DB::table('hr_attendance')->insert($chunk);
        }
    }

    /** Three months posted and paid; this month prepared and waiting for the CEO. */
    private function payrollHistory(User $hrManager, ?User $ceo, ?User $accountant): void
    {
        if (PayrollRun::query()->exists() || ! $ceo || ! $accountant) {
            return;
        }

        $bank = Account::query()->where('system_key', 'bank')->first();

        try {
            foreach ([3, 2, 1] as $back) {
                $start = now()->startOfMonth()->subMonths($back);
                ['run' => $run] = $this->payroll->prepare($start->format('Y-m'), $hrManager, 'Monthly payroll');
                $this->payroll->authorise($run, $ceo);
                $this->payroll->lockRun($run, $ceo);
                $this->payroll->post($run, $accountant);

                if ($bank) {
                    $this->payroll->pay($run, $bank->id, $start->copy()->endOfMonth()->subDays(2)->toDateString(), $accountant);
                }
            }

            $this->payroll->prepare(now()->format('Y-m'), $hrManager, 'Monthly payroll, includes Hassan\'s commission');
        } catch (RuntimeException $e) {
            $this->command?->warn("HR demo: payroll history stopped: {$e->getMessage()}");
        }
    }

    /** @param  array<string, int>  $departments */
    private function recruitment(array $departments, User $hrManager): void
    {
        if (Vacancy::query()->exists()) {
            return;
        }

        $qc = Vacancy::create([
            'title' => 'Quality Controller', 'department_id' => $departments['Quality Assurance'] ?? null, 'positions' => 1,
            'employment_type' => 'permanent', 'location' => 'Mbezi factory, Dar es Salaam', 'status' => 'filled',
            'description' => 'Diploma in food science or chemistry; TBS standards experience preferred.',
            'closing_date' => now()->subMonths(2)->toDateString(), 'created_by' => $hrManager->id,
        ]);

        $hired = Employee::query()->where('employee_number', 'WC-0213')->first() ?? $this->employee([
            'employee_number' => 'WC-0213', 'full_name' => 'Zawadi Kimaro', 'email' => 'zawadi.kimaro@gmail.com', 'phone' => '0754 000 111',
            'job_title' => 'Quality Controller', 'grade' => 'O1', 'department_id' => $departments['Quality Assurance'] ?? null,
            'gender' => 'female', 'date_of_birth' => '1998-06-06', 'hire_date' => now()->startOfMonth()->subMonth()->addDays(14)->toDateString(),
            'employment_type' => 'permanent', 'bank_name' => 'CRDB', 'address' => 'Kimara, Dar es Salaam',
        ], 820000, 0, 70000, $hrManager, 'permanent');

        foreach (OnboardingTask::DEFAULTS as $i => $title) {
            $hired->onboardingTasks()->firstOrCreate(['title' => $title], [
                'sort' => $i + 1, 'done_at' => $i < 4 ? now()->subDays(20 - $i) : null, 'done_by' => $i < 4 ? $hrManager->id : null,
            ]);
        }

        $qc->applicants()->createMany([
            ['name' => 'Zawadi Kimaro', 'email' => 'zawadi.kimaro@gmail.com', 'phone' => '0754 000 111', 'stage' => 'hired', 'employee_id' => $hired->id, 'notes' => 'Strong practical test'],
            ['name' => 'Peter Mushi', 'phone' => '0713 222 909', 'stage' => 'rejected', 'notes' => 'No laboratory experience'],
        ]);

        $driver = Vacancy::create([
            'title' => 'Heavy Goods Driver', 'department_id' => $departments['Transport & Logistics'] ?? null, 'positions' => 2,
            'employment_type' => 'fixed_term', 'location' => 'Dar es Salaam to Arusha route', 'status' => 'open',
            'description' => 'Class E licence, five years on long-distance routes, clean record.',
            'closing_date' => now()->addDays(21)->toDateString(), 'created_by' => $hrManager->id,
        ]);
        $driver->applicants()->createMany([
            ['name' => 'Rashidi Mfaume', 'phone' => '0715 330 118', 'stage' => 'interview', 'notes' => 'Ten years with a Dar to Mwanza transporter'],
            ['name' => 'Godfrey Lyimo', 'phone' => '0767 104 552', 'stage' => 'screening'],
            ['name' => 'Selemani Ally', 'phone' => '0688 451 203', 'stage' => 'applied'],
            ['name' => 'Joseph Haule', 'phone' => '0744 908 117', 'stage' => 'offer', 'notes' => 'Offer at TZS 750,000 basic sent'],
        ]);

        $rep = Vacancy::create([
            'title' => 'Sales Representative, Dodoma', 'department_id' => $departments['Sales'] ?? null, 'positions' => 1,
            'employment_type' => 'permanent', 'location' => 'Dodoma', 'status' => 'open',
            'closing_date' => now()->addDays(35)->toDateString(), 'created_by' => $hrManager->id,
        ]);
        $rep->applicants()->createMany([
            ['name' => 'Neema Chacha', 'email' => 'neema.chacha@yahoo.com', 'stage' => 'applied'],
            ['name' => 'Emmanuel Kisanga', 'stage' => 'screening'],
        ]);
    }

    /** @param  array<string, Employee>  $people */
    private function performance(array $people, User $hrManager): void
    {
        if (AppraisalPeriod::query()->exists()) {
            return;
        }

        $year = now()->year;
        $midYear = AppraisalPeriod::create(['name' => "{$year} mid-year review", 'start_date' => "{$year}-01-01", 'end_date' => "{$year}-06-30", 'status' => 'closed']);
        $annual = AppraisalPeriod::create(['name' => "{$year} annual review", 'start_date' => "{$year}-01-01", 'end_date' => "{$year}-12-31", 'status' => 'open']);

        $objectives = [
            'WC-0201' => [['Line uptime above 92%', '92%', 3, 4], ['Zero lost-time injuries', '0', 2, 5], ['Changeovers under 25 minutes', '25 min', 1, 3]],
            'WC-0204' => [['Batch release within 24 hours', '24 h', 2, 4], ['TBS audit findings closed', '100%', 2, 5]],
            'WC-0206' => [['Arusha volume 4,500 cartons a month', '4,500', 3, 3], ['New outlets opened', '12', 1, 4]],
            'WC-0210' => [['Planned maintenance completed on time', '95%', 2, 4], ['Compressor downtime', '< 6 h', 1, 3]],
            'WC-0205' => [['On-time deliveries', '97%', 2, 4], ['Fuel within standard', '±3%', 1, 3]],
        ];

        foreach ($objectives as $number => $rows) {
            if (! $employee = $people[$number] ?? null) {
                continue;
            }

            $appraisal = Appraisal::create([
                'period_id' => $midYear->id, 'employee_id' => $employee->id, 'reviewer_id' => $employee->manager?->user_id ?? $hrManager->id,
                'status' => 'completed', 'reviewer_comments' => 'Reliable and improving; keep the focus on the first objective.',
                'employee_comments' => 'Thank you. I would like training on the new filler.', 'completed_at' => now()->setDate($year, 7, 15),
            ]);
            foreach ($rows as [$title, $target, $weight, $rating]) {
                $appraisal->objectives()->create(['title' => $title, 'target' => $target, 'weight' => $weight, 'rating' => $rating]);
            }
            $appraisal->update(['overall_rating' => $appraisal->weightedRating()]);

            $open = Appraisal::create(['period_id' => $annual->id, 'employee_id' => $employee->id, 'reviewer_id' => $appraisal->reviewer_id, 'status' => 'draft']);
            foreach ($rows as [$title, $target, $weight]) {
                $open->objectives()->create(['title' => $title, 'target' => $target, 'weight' => $weight]);
            }
        }

        $trainings = [
            ['WC-0201', 'Krones filler operation', 'Krones East Africa', -60, -57, 1800000, 'completed'],
            ['WC-0202', 'Krones filler operation', 'Krones East Africa', -60, -57, 1800000, 'completed'],
            ['WC-0204', 'HACCP and food safety', 'TBS Training Centre', -30, -28, 650000, 'completed'],
            ['WC-0205', 'Defensive driving refresher', 'NIT Dar es Salaam', 10, 12, 320000, 'planned'],
            ['WC-0210', 'Industrial electrical safety', 'VETA Chang\'ombe', -5, 5, 450000, 'in_progress'],
        ];
        foreach ($trainings as [$number, $title, $provider, $from, $to, $cost, $status]) {
            if ($employee = $people[$number] ?? null) {
                Training::create([
                    'employee_id' => $employee->id, 'title' => $title, 'provider' => $provider,
                    'start_date' => now()->addDays($from)->toDateString(), 'end_date' => now()->addDays($to)->toDateString(),
                    'cost' => $cost, 'status' => $status,
                ]);
            }
        }
    }

    /** @param  array<string, Employee>  $people */
    private function discipline(array $people, User $hrManager): void
    {
        if (DisciplineCase::query()->exists()) {
            return;
        }

        if ($elia = $people['WC-0203'] ?? null) {
            DisciplineCase::create([
                'employee_id' => $elia->id, 'number' => $this->numbers->next('DSC'), 'category' => 'absenteeism',
                'incident_date' => now()->subDays(9)->toDateString(),
                'description' => 'Absent without notice on two shifts in one week; supervisor could not reach him by phone.',
                'action' => 'written_warning', 'status' => 'open', 'opened_by' => $hrManager->id,
            ]);
        }

        if ($ibrahim = $people['WC-0209'] ?? null) {
            DisciplineCase::create([
                'employee_id' => $ibrahim->id, 'number' => $this->numbers->next('DSC'), 'category' => 'lateness',
                'incident_date' => now()->subMonths(4)->toDateString(), 'description' => 'Late for the night handover three times in March.',
                'action' => 'verbal_warning', 'status' => 'closed', 'outcome' => 'Counselled; no repeat since.',
                'opened_by' => $hrManager->id, 'closed_by' => $hrManager->id, 'closed_at' => now()->subMonths(4)->addDays(6),
            ]);
        }
    }

    /** @param  array<string, Employee>  $people */
    private function exits(array $people, User $hrManager): void
    {
        if (Separation::query()->exists() || ! ($daudi = $people['WC-0207'] ?? null)) {
            return;
        }

        $separation = $this->separations->open($daudi, [
            'type' => 'resignation', 'notice_date' => now()->subDays(10)->toDateString(),
            'last_working_day' => now()->addDays(20)->toDateString(),
            'reason' => 'Relocating to Mwanza to join a family business', 'other_dues' => 0,
        ], $hrManager);

        foreach ($separation->items()->orderBy('id')->limit(2)->get() as $item) {
            $item->update(['cleared_by' => $hrManager->id, 'cleared_at' => now()->subDays(2), 'note' => 'Done']);
        }
    }

    private function phone(string $seed): string
    {
        $n = abs(crc32($seed));

        return sprintf('07%d%d %03d %03d', 1 + $n % 8, $n % 10, ($n >> 4) % 1000, ($n >> 12) % 1000);
    }
}
