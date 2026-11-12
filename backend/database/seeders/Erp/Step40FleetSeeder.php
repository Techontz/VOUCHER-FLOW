<?php

namespace Database\Seeders\Erp;

use App\Models\Company;
use App\Models\Erp\Account;
use App\Models\Erp\Customer;
use App\Models\Erp\Fleet\FleetDowntime;
use App\Models\Erp\Fleet\FleetDriver;
use App\Models\Erp\Fleet\FleetFuelStandard;
use App\Models\Erp\Fleet\FleetMaintenanceSchedule;
use App\Models\Erp\Fleet\FleetTrip;
use App\Models\Erp\Fleet\FleetTyre;
use App\Models\Erp\Fleet\FleetVehicle;
use App\Models\Erp\Supplier;
use App\Models\User;
use App\Services\Erp\Fleet\FleetMaintenance;
use App\Services\Erp\Fleet\FleetTrips;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Database\Seeder;

/**
 * Watercom's fleet: six company trucks and two hired, six drivers, fuel
 * standards, and a month of trips from Dar es Salaam to Morogoro, Dodoma,
 * Arusha and Mwanza, all run through the real trip service so every closed
 * trip has posted its costs and charges exactly as a person would have.
 *
 * Left open for the demo: trucks on the road now, trips planned for today and
 * tomorrow, one trip over its fuel standard waiting for an approver, a
 * driver's fuel receipt waiting for approval, a truck in the garage, a service
 * due soon and an insurance expiring within the month.
 *
 * Re-runnable: people, suppliers and vehicles are matched on natural keys,
 * and the trip history is written only into a company that has none.
 */
class Step40FleetSeeder extends Seeder
{
    /** Round-trip km and days on the road from the Mbezi factory. */
    private const ROUTES = [
        'Morogoro' => [390, 1],
        'Dodoma' => [900, 2],
        'Arusha' => [1280, 3],
        'Mwanza' => [2300, 4],
    ];

    private const FUEL_PRICE = 3150;

    public function __construct(
        private readonly TenantContext $tenant,
        private readonly FleetTrips $trips,
        private readonly FleetMaintenance $maintenance,
    ) {}

    public function run(): void
    {
        $company = $this->tenant->company();

        if (! $company) {
            return;
        }

        $modules = $company->modules ?? [];
        if (! in_array('fleet', $modules, true)) {
            $company->forceFill(['modules' => array_values(array_unique([...$modules, 'fleet']))])->save();
        }

        mt_srand(4040);

        $people = $this->people($company);
        $suppliers = $this->suppliers($company);
        $vehicles = $this->vehicles($company, $suppliers);
        $drivers = $this->drivers($company, $people, $vehicles);
        $this->standards($company, $vehicles);

        if (! FleetTrip::query()->exists()) {
            $this->history($people, $suppliers, $vehicles, $drivers);
            $this->upkeep($people['manager'], $suppliers, $vehicles);
        }
    }

    /** @return array<string, User> */
    private function people(Company $company): array
    {
        $rows = [
            'manager' => ['Godfrey Mollel', 'godfrey.mollel@watercom.test', User::ROLE_FLEET_MANAGER, 'Fleet Manager', 'WC-0401'],
            'dispatch' => ['Rehema Kweka', 'rehema.kweka@watercom.test', User::ROLE_DISPATCH, 'Dispatch Officer', 'WC-0402'],
            'juma' => ['Juma Mrisho', 'juma.mrisho@watercom.test', User::ROLE_DRIVER, 'Driver', 'WC-0411'],
            'salim' => ['Salim Kombo', 'salim.kombo@watercom.test', User::ROLE_DRIVER, 'Driver', 'WC-0412'],
            'daudi' => ['Daudi Massawe', 'daudi.massawe@watercom.test', User::ROLE_DRIVER, 'Driver', 'WC-0413'],
            'ally' => ['Ally Mfinanga', 'ally.mfinanga@watercom.test', User::ROLE_DRIVER, 'Driver', 'WC-0414'],
            'musa' => ['Musa Lyimo', 'musa.lyimo@watercom.test', User::ROLE_DRIVER, 'Driver', 'WC-0415'],
            'yusuf' => ['Yusuf Mbwana', 'yusuf.mbwana@watercom.test', User::ROLE_DRIVER, 'Driver', 'WC-0416'],
        ];

        $people = [];
        foreach ($rows as $key => [$name, $email, $role, $title, $code]) {
            $people[$key] = User::query()->where('email', $email)->first() ?? User::create([
                'company_id' => $company->id, 'name' => $name, 'email' => $email, 'password' => 'Password123!',
                'role' => $role, 'job_title' => $title, 'employee_code' => $code,
                'status' => 'active', 'locale' => 'sw', 'email_verified_at' => now(),
            ]);
        }

        return $people;
    }

    /** @return array<string, Supplier> */
    private function suppliers(Company $company): array
    {
        $rows = [
            'kili' => ['SUP-FLT-01', 'Kilimanjaro Truck Hire Ltd', 'Vehicle hire', 'Elia Swai', '+255 755 330 118', 'Arusha'],
            'lake' => ['SUP-FLT-02', 'Lake Zone Haulage Co', 'Vehicle hire', 'Masanja Kulwa', '+255 768 412 090', 'Mwanza'],
            'garage' => ['SUP-FLT-03', 'Kariakoo Motors Garage', 'Fleet', 'Abdallah Said', '+255 715 880 214', 'Dar es Salaam'],
            'puma' => ['SUP-FLT-04', 'Puma Energy Ubungo', 'Fuel', 'Neema Lukumay', '+255 22 245 0011', 'Dar es Salaam'],
        ];

        $suppliers = [];
        foreach ($rows as $key => [$code, $name, $cat, $contact, $phone, $city]) {
            $suppliers[$key] = Supplier::firstOrCreate(['code' => $code], [
                'company_id' => $company->id, 'name' => $name, 'category' => $cat, 'contact_person' => $contact,
                'phone' => $phone, 'city' => $city, 'payment_terms_days' => 14,
            ]);
        }

        return $suppliers;
    }

    /** @return array<string, FleetVehicle> */
    private function vehicles(Company $company, array $suppliers): array
    {
        $today = CarbonImmutable::today();
        // reg, make, model, type, capacity t, odometer, insurance expiry, licence expiry, monthly insurance, licence, depreciation
        $owned = [
            'isuzu' => ['T 101 DXA', 'Isuzu', 'FVZ 1400', 'truck', 10, 148200, $today->addMonths(7), $today->addMonths(5), 520000, 95000, 1850000],
            'fuso' => ['T 214 DYB', 'Mitsubishi', 'Fuso Fighter', 'truck', 8, 201400, $today->addDays(18), $today->addMonths(3), 430000, 85000, 1400000],
            'scania' => ['T 327 DZC', 'Scania', 'P410', 'truck', 28, 312800, $today->addMonths(10), $today->addMonths(8), 980000, 160000, 3600000],
            'npr' => ['T 438 EAA', 'Isuzu', 'NPR 71', 'truck', 4, 96300, $today->addMonths(4), $today->addDays(26), 260000, 60000, 900000],
            'tata' => ['T 552 EBB', 'Tata', 'LPT 1618', 'truck', 15, 174900, $today->addMonths(9), $today->addMonths(6), 610000, 110000, 2100000],
            'dyna' => ['T 663 ECC', 'Toyota', 'Dyna', 'pickup', 3, 58700, $today->addMonths(2), $today->addMonths(11), 180000, 45000, 650000],
        ];

        $vehicles = [];
        foreach ($owned as $key => [$reg, $make, $model, $type, $cap, $odo, $ins, $lic, $mIns, $mLic, $mDep]) {
            $vehicles[$key] = FleetVehicle::firstOrCreate(['registration_number' => $reg], [
                'company_id' => $company->id, 'make' => $make, 'model' => $model, 'type' => $type,
                'year' => 2016 + (strlen($reg) % 6), 'capacity' => $cap, 'capacity_unit' => 'tonnes', 'ownership' => 'owned',
                'odometer' => $odo, 'insurer' => 'Jubilee Allianz', 'insurance_policy_number' => 'JA-MV-'.substr(md5($reg), 0, 6),
                'insurance_expiry' => $ins, 'road_licence_number' => 'RL-'.str_replace(' ', '', $reg), 'road_licence_expiry' => $lic,
                'monthly_insurance' => $mIns, 'monthly_licence' => $mLic, 'monthly_depreciation' => $mDep, 'allocation_basis' => 'days',
            ]);
        }

        $vehicles['kili'] = FleetVehicle::firstOrCreate(['registration_number' => 'T 771 EDD'], [
            'company_id' => $company->id, 'make' => 'Mercedes-Benz', 'model' => 'Actros 2641', 'type' => 'truck', 'capacity' => 30,
            'ownership' => 'hired', 'supplier_id' => $suppliers['kili']->id, 'hire_rate_basis' => 'per_km', 'hire_rate' => 1900,
            'hire_includes_fuel' => true, 'odometer' => 402100, 'notes' => 'Wet hire: the owner fuels the truck.',
        ]);
        $vehicles['lake'] = FleetVehicle::firstOrCreate(['registration_number' => 'T 884 EEE'], [
            'company_id' => $company->id, 'make' => 'FAW', 'model' => 'J5P', 'type' => 'truck', 'capacity' => 20,
            'ownership' => 'hired', 'supplier_id' => $suppliers['lake']->id, 'hire_rate_basis' => 'per_trip', 'hire_rate' => 1350000,
            'hire_includes_fuel' => false, 'odometer' => 255400, 'notes' => 'Dry hire: Watercom fuels the truck.',
        ]);

        return $vehicles;
    }

    /** @return array<string, FleetDriver> by vehicle key */
    private function drivers(Company $company, array $people, array $vehicles): array
    {
        $rows = [
            'isuzu' => ['juma', 'DL-4002198871', 'E', 14],
            'fuso' => ['salim', 'DL-4002301145', 'E', 400],
            'scania' => ['daudi', 'DL-4001874420', 'E', 600],
            'npr' => ['ally', 'DL-4002455019', 'C', 22],
            'tata' => ['musa', 'DL-4002011736', 'E', 300],
            'dyna' => ['yusuf', 'DL-4002587302', 'C', 500],
        ];

        $drivers = [];
        foreach ($rows as $vehicle => [$person, $licence, $class, $expiresIn]) {
            $drivers[$vehicle] = FleetDriver::firstOrCreate(['user_id' => $people[$person]->id], [
                'company_id' => $company->id, 'licence_number' => $licence, 'licence_class' => $class,
                'licence_expiry' => today()->addDays($expiresIn), 'phone' => '+255 7'.mt_rand(10, 89).' '.mt_rand(100, 999).' '.mt_rand(100, 999),
                'vehicle_id' => $vehicles[$vehicle]->id, 'daily_allowance' => 25000,
            ]);
        }

        return $drivers;
    }

    private function standards(Company $company, array $vehicles): void
    {
        if (FleetFuelStandard::query()->exists()) {
            return;
        }

        foreach (['isuzu' => 32, 'fuso' => 28, 'scania' => 42, 'npr' => 18, 'tata' => 33, 'dyna' => 14, 'lake' => 38] as $key => $litres) {
            FleetFuelStandard::create(['company_id' => $company->id, 'vehicle_id' => $vehicles[$key]->id, 'basis' => 'per_100km', 'litres' => $litres, 'tolerance_percent' => 10]);
        }

        // The Scania on the Dodoma run climbs the escarpment loaded: a route figure of its own.
        FleetFuelStandard::create(['company_id' => $company->id, 'vehicle_id' => $vehicles['scania']->id, 'origin' => 'Dar es Salaam', 'destination' => 'Dodoma', 'basis' => 'per_trip', 'litres' => 400, 'tolerance_percent' => 8, 'notes' => 'Loaded up, empty back']);
        FleetFuelStandard::create(['company_id' => $company->id, 'origin' => 'Dar es Salaam', 'destination' => 'Morogoro', 'basis' => 'per_100km', 'litres' => 30, 'tolerance_percent' => 12]);
    }

    /** A month of trips, most of them closed and on the books, the rest at every other stage. */
    private function history(array $people, array $suppliers, array $vehicles, array $drivers): void
    {
        $manager = $people['manager'];
        $cash = Account::query()->where('system_key', 'cash')->value('id');
        $customers = Customer::query()->orderBy('code')->get()->values();
        $start = CarbonImmutable::today()->subDays(30);
        $lo = 300;

        $plan = function (string $key, string $option, string $to, CarbonImmutable $when, array $extra = []) use ($vehicles, $drivers, $customers, $manager, &$lo) {
            [$km] = self::ROUTES[$to];
            $customer = $customers[($lo + strlen($to)) % max(1, $customers->count())] ?? null;
            $charged = in_array($option, ['charged', 'hired'], true);

            return $this->trips->create([
                'cost_option' => $option,
                'vehicle_id' => $vehicles[$key]->id ?? null,
                'driver_id' => $drivers[$key]->id ?? null,
                'customer_id' => $customer?->id,
                'origin' => 'Dar es Salaam', 'destination' => $to, 'distance_km' => $km,
                'planned_start' => $when->setTime(6, 0)->toDateTimeString(),
                'planned_end' => $when->addDays(self::ROUTES[$to][1] - 1)->setTime(18, 0)->toDateTimeString(),
                'source_type' => 'loading_order', 'source_id' => $lo, 'source_reference' => sprintf('LO-%s-%06d', $when->format('Y'), $lo++),
                'cargo_description' => $this->cargo($vehicles[$key]->capacity ?? 10),
                'transport_charge' => $charged ? round($km * 1100, -4) : 0,
                ...$extra,
            ], $manager);
        };

        // Runs a trip to the stage asked for; fuel factor 1 burns exactly the standard.
        $drive = function (FleetTrip $trip, CarbonImmutable $when, string $until = 'closed', float $fuelFactor = 1.0, ?User $fuelBy = null) use ($manager, $cash, $suppliers) {
            [$km, $days] = self::ROUTES[$trip->destination];
            $out = $trip->vehicle ? (float) $trip->vehicle->fresh()->odometer : null;
            $this->trips->dispatch($trip, $out, $when->setTime(6, 15)->toDateTimeString(), $manager);

            if ($until === 'dispatched') {
                return $trip;
            }

            $end = $when->addDays($days - 1)->setTime(17, 40);

            if ($trip->usesCompanyVehicle() || ($trip->vehicle && ! $trip->vehicle->hire_includes_fuel)) {
                $standard = $this->trips->standardFor($trip);
                $litres = round(($standard ? $standard->litresFor($km) : $km * 0.3) * $fuelFactor * (mt_rand(94, 104) / 100), 1);
                $first = round($litres * 0.6, 1);
                $onCredit = mt_rand(0, 2) === 0;
                foreach ([[$first, 'Puma Energy Ubungo', $when], [$litres - $first, $this->station($trip->destination), $when->addDays(max(0, $days - 1))]] as $i => [$l, $station, $date]) {
                    $this->trips->recordFuel($trip, [
                        'litres' => $l, 'price_per_litre' => self::FUEL_PRICE + ($i ? 70 : 0), 'station' => $station,
                        'receipt_number' => 'FR-'.mt_rand(100000, 999999), 'issue_date' => $date->toDateString(),
                        ...($onCredit && $i === 0 ? ['supplier_id' => $suppliers['puma']->id] : ['account_id' => $cash]),
                    ], $fuelBy && $i === 1 ? $fuelBy : $manager);
                }
            }

            if ($trip->driver_id) {
                $this->trips->recordExpense($trip, ['type' => 'allowance', 'quantity' => $days, 'account_id' => $cash, 'expense_date' => $when->toDateString(), 'description' => 'Per diem'], $manager);
            }
            if ($km > 500) {
                $this->trips->recordExpense($trip, ['type' => 'toll', 'rate' => mt_rand(3, 8) * 5000, 'account_id' => $cash, 'expense_date' => $when->toDateString(), 'description' => 'Weighbridge and road toll', 'receipt_number' => 'TRA-'.mt_rand(10000, 99999)], $manager);
            }
            if ($trip->usesCompanyVehicle() && mt_rand(0, 1)) {
                $this->trips->recordExpense($trip, ['type' => 'loading', 'rate' => mt_rand(4, 12) * 5000, 'account_id' => $cash, 'expense_date' => $end->toDateString(), 'description' => 'Offloading crew at the depot'], $manager);
            }
            if (mt_rand(0, 2) === 0) {
                $this->trips->recordExpense($trip, ['type' => 'parking', 'rate' => 5000, 'quantity' => $days, 'account_id' => $cash, 'expense_date' => $end->toDateString(), 'description' => 'Secure overnight parking'], $manager);
            }

            $in = $trip->vehicle && $out !== null ? $out + $km + mt_rand(-15, 25) : null;
            $this->trips->complete($trip, $in, $end->toDateTimeString(), $manager);

            if ($until === 'completed') {
                return $trip;
            }

            return $this->trips->close($trip, null, $manager);
        };

        // Each company truck runs back to back through the month.
        $runs = [
            'isuzu' => ['Morogoro', 'Arusha', 'Dodoma', 'Morogoro', 'Arusha'],
            'fuso' => ['Dodoma', 'Morogoro', 'Morogoro', 'Dodoma'],
            'scania' => ['Mwanza', 'Dodoma', 'Mwanza'],
            'npr' => ['Morogoro', 'Morogoro', 'Dodoma', 'Morogoro', 'Morogoro'],
            'tata' => ['Arusha', 'Mwanza', 'Morogoro'],
            'dyna' => ['Morogoro', 'Morogoro', 'Morogoro', 'Dodoma', 'Morogoro'],
        ];

        foreach ($runs as $key => $routes) {
            $when = $start->addDays(mt_rand(0, 2));
            foreach ($routes as $i => $to) {
                if ($when->gt(CarbonImmutable::today()->subDays(5))) {
                    break;
                }
                $trip = $plan($key, $i % 3 === 1 ? 'included' : 'charged', $to, $when);
                $drive($trip, $when);
                $when = $when->addDays(self::ROUTES[$to][1] + mt_rand(1, 2));
            }
        }

        // The hired trucks: the wet hire to Mwanza twice, the dry hire to Dodoma.
        $wet = CarbonImmutable::today()->subDays(24);
        $drive($plan('kili', 'hired', 'Mwanza', $wet, ['driver_id' => null]), $wet);
        $wet = CarbonImmutable::today()->subDays(14);
        $drive($plan('kili', 'hired', 'Mwanza', $wet, ['driver_id' => null]), $wet);
        $dry = CarbonImmutable::today()->subDays(11);
        $drive($plan('lake', 'hired', 'Dodoma', $dry, ['driver_id' => null, 'transport_charge' => 0, 'customer_id' => null]), $dry);

        // A customer collecting with their own truck: no cost to Watercom.
        $collect = $this->trips->create([
            'cost_option' => 'customer_vehicle', 'customer_id' => $customers[1]->id ?? $customers[0]->id, 'external_vehicle' => 'T 905 DKL',
            'origin' => 'Dar es Salaam', 'destination' => 'Kariakoo', 'distance_km' => 0,
            'planned_start' => CarbonImmutable::today()->subDays(8)->setTime(9, 0)->toDateTimeString(),
            'source_type' => 'loading_order', 'source_id' => $lo, 'source_reference' => sprintf('LO-%s-%06d', now()->format('Y'), $lo++),
            'cargo_description' => '420 cartons Watercom 500ml x 24, collected at the gate',
        ], $manager);
        $this->trips->dispatch($collect, null, CarbonImmutable::today()->subDays(8)->setTime(9, 30)->toDateTimeString(), $manager);
        $this->trips->complete($collect, null, CarbonImmutable::today()->subDays(8)->setTime(11, 0)->toDateTimeString(), $manager);
        $this->trips->close($collect, null, $manager);

        // Over the standard and waiting: the Scania burned a quarter more than allowed to Dodoma.
        $over = CarbonImmutable::today()->subDays(3);
        $drive($plan('scania', 'charged', 'Dodoma', $over), $over, 'completed', 1.25);

        // On the road now; the driver's own fuel receipt waits for approval.
        $now = CarbonImmutable::today()->subDay();
        $onRoad = $plan('isuzu', 'charged', 'Arusha', $now);
        $drive($onRoad, $now, 'dispatched');
        $this->trips->recordFuel($onRoad, ['litres' => 180, 'price_per_litre' => self::FUEL_PRICE, 'station' => 'Lake Oil Chalinze', 'receipt_number' => 'FR-552031', 'account_id' => $cash], $people['juma']);
        $tata = $plan('tata', 'included', 'Dodoma', CarbonImmutable::today());
        $drive($tata, CarbonImmutable::today(), 'dispatched');

        // Planned for today and tomorrow, and one called off.
        $plan('npr', 'charged', 'Morogoro', CarbonImmutable::today());
        $plan('dyna', 'included', 'Morogoro', CarbonImmutable::today()->addDay());
        $cancelled = $plan('dyna', 'charged', 'Dodoma', CarbonImmutable::today()->subDays(6));
        $this->trips->cancel($cancelled, 'Customer moved the delivery to next week', $manager);
    }

    /** Service schedules, posted services and a draft, tyres, and the Fuso in the garage. */
    private function upkeep(User $manager, array $suppliers, array $vehicles): void
    {
        $cash = Account::query()->where('system_key', 'cash')->value('id');

        foreach (['isuzu', 'fuso', 'scania', 'npr', 'tata', 'dyna'] as $i => $key) {
            $vehicle = $vehicles[$key]->fresh();
            $odo = (float) $vehicle->odometer;
            // The Isuzu is 600 km from its oil service; the Tata is past its date.
            $lastKm = match ($key) {
                'isuzu' => $odo - 9400,
                default => $odo - 2000 - $i * 1100,
            };
            $schedule = FleetMaintenanceSchedule::create([
                'vehicle_id' => $vehicle->id, 'title' => 'Engine oil, filters and greasing', 'interval_km' => 10000, 'interval_days' => 90,
                'last_done_odometer' => $lastKm, 'last_done_date' => today()->subDays($key === 'tata' ? 96 : 20 + $i * 9),
            ]);
            $schedule->recomputeNextDue();
            $schedule->save();

            $brakes = FleetMaintenanceSchedule::create([
                'vehicle_id' => $vehicle->id, 'title' => 'Brake inspection', 'interval_days' => 180,
                'last_done_date' => today()->subDays(40 + $i * 12),
            ]);
            $brakes->recomputeNextDue();
            $brakes->save();

            if (in_array($key, ['fuso', 'scania', 'dyna'], true)) {
                $record = $this->maintenance->createService([
                    'vehicle_id' => $vehicle->id, 'schedule_id' => $schedule->id,
                    'service_date' => today()->subDays(20 + $i * 9)->toDateString(), 'odometer' => $lastKm,
                    'work_done' => 'Engine oil 15W-40, oil and fuel filters, greasing', 'cost' => 380000 + $i * 45000,
                    'supplier_id' => $suppliers['garage']->id, 'invoice_number' => 'KMG-'.(4100 + $i),
                ], $manager);
                $this->maintenance->postService($record, $manager);
            }
        }

        $this->maintenance->postService($this->maintenance->createService([
            'vehicle_id' => $vehicles['npr']->id, 'service_date' => today()->subDays(9)->toDateString(),
            'work_done' => 'Replaced the alternator belt on the roadside, Chalinze', 'cost' => 85000, 'account_id' => $cash,
        ], $manager), $manager);

        // The Fuso is in the garage now: clutch job, quoted, not yet posted.
        $clutch = $this->maintenance->createService([
            'vehicle_id' => $vehicles['fuso']->id, 'service_date' => today()->toDateString(), 'odometer' => $vehicles['fuso']->fresh()->odometer,
            'work_done' => 'Clutch plate and pressure plate replacement', 'cost' => 1450000,
            'supplier_id' => $suppliers['garage']->id, 'invoice_number' => 'KMG-4188',
        ], $manager);
        if (! FleetDowntime::query()->whereNull('ended_at')->exists()) {
            $this->maintenance->startDowntime(['vehicle_id' => $vehicles['fuso']->id, 'reason' => 'maintenance', 'description' => 'Clutch slipping under load', 'service_record_id' => $clutch->id, 'started_at' => now()->subHours(20)], $manager);
        }

        // A closed spell of downtime for the history.
        $past = $this->maintenance->startDowntime(['vehicle_id' => $vehicles['npr']->id, 'reason' => 'breakdown', 'description' => 'Alternator belt snapped near Chalinze', 'started_at' => now()->subDays(9)->setTime(10, 0)], $manager);
        $this->maintenance->endDowntime($past, now()->subDays(9)->setTime(16, 30)->toDateTimeString(), $manager);

        // Tyres on the Scania, one replaced this month.
        $scania = $vehicles['scania']->fresh();
        $positions = ['Steer left', 'Steer right', 'Drive 1 left outer', 'Drive 1 right outer', 'Drive 2 left outer', 'Drive 2 right outer'];
        foreach ($positions as $i => $position) {
            if (FleetTyre::query()->where('serial_number', 'BS-R249-'.(7310 + $i))->exists()) {
                continue;
            }
            $tyre = $this->maintenance->fitTyre([
                'vehicle_id' => $scania->id, 'position' => $position, 'serial_number' => 'BS-R249-'.(7310 + $i),
                'brand' => 'Bridgestone', 'size' => '315/80R22.5', 'cost' => 1150000,
                'fitted_date' => today()->subMonths(5)->toDateString(), 'fitted_odometer' => (float) $scania->odometer - 38000,
            ], $manager);

            if ($i === 2) {
                $this->maintenance->removeTyre($tyre, ['removed_date' => today()->subDays(12)->toDateString(), 'removed_odometer' => (float) $scania->odometer - 4200, 'removal_reason' => 'Sidewall cut on the Singida road'], $manager);
                $this->maintenance->fitTyre([
                    'vehicle_id' => $scania->id, 'position' => $position, 'serial_number' => 'MS-X2-55120', 'brand' => 'Michelin', 'size' => '315/80R22.5',
                    'cost' => 1320000, 'fitted_date' => today()->subDays(12)->toDateString(), 'fitted_odometer' => (float) $scania->odometer - 4200,
                ], $manager);
            }
        }
    }

    private function cargo(float|string $capacity): string
    {
        $cartons = (int) round((float) $capacity * 70 / 10) * 10;

        return [
            "{$cartons} cartons Watercom 500ml x 24",
            "{$cartons} cartons Watercom 1.5L x 12",
            (int) ($cartons / 2).' cartons 500ml and '.(int) ($cartons / 2).' cartons 1.5L',
        ][mt_rand(0, 2)];
    }

    private function station(string $town): string
    {
        return match ($town) {
            'Morogoro' => 'Total Energies Msamvu',
            'Dodoma' => 'Puma Energy Dodoma',
            'Arusha' => 'Oryx Njiro Arusha',
            'Mwanza' => 'Lake Oil Buzuruga',
            default => 'Puma Energy Ubungo',
        };
    }
}
