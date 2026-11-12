<?php

namespace Database\Seeders;

use App\Models\Company;
use App\Models\Erp\Customer;
use App\Models\Erp\Product;
use App\Models\Erp\ProductCategory;
use App\Models\Erp\StockDocument;
use App\Models\Erp\Supplier;
use App\Models\Erp\Unit;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Services\Erp\BusinessSetup;
use App\Services\Erp\StockDocuments;
use App\Support\TenantContext;
use Illuminate\Database\Seeder;

/**
 * Watercom as a working beverage factory: ERP staff, products from preforms
 * to finished cartons, two stores, suppliers, customers and real posted stock
 * documents, so every ERP screen has something true to show and every action
 * can be tried.
 *
 * Re-runnable. People, products and parties are matched on their natural keys,
 * and the stock history is written only into a company that has none.
 */
class ErpDemoSeeder extends Seeder
{
    public function __construct(
        private readonly TenantContext $tenant,
        private readonly BusinessSetup $setup,
        private readonly StockDocuments $documents,
    ) {}

    public function run(): void
    {
        $company = Company::query()->where('email', 'info@watercom.co.tz')->first();

        if (! $company) {
            return;
        }

        $admin = User::query()->where('email', 'admin@watercom.test')->firstOrFail();

        // Once: a re-run of setup is an administrator's act and is audited as one.
        if (! $company->setup_completed_at) {
            $this->setup->apply($company, 'beverage', null, [], $admin);
        }

        $this->tenant->forCompany($company->fresh(), function () use ($company) {
            $staff = $this->people($company);
            $places = $this->places($company);
            $products = $this->products($company);
            $suppliers = $this->suppliers($company);
            $this->customers($company);

            if (! StockDocument::query()->exists()) {
                $this->history($places, $products, $suppliers, $staff);
            }

            // Module demo data (database/seeders/Erp), in file-name order, so a
            // module can build on the ones before it. Each seeder is idempotent.
            $files = glob(__DIR__.'/Erp/*Seeder.php') ?: [];
            sort($files);
            foreach ($files as $file) {
                $this->call('Database\\Seeders\\Erp\\'.basename($file, '.php'));
            }
        });
    }

    /** @return array<string, User> */
    private function people(Company $company): array
    {
        $rows = [
            'storekeeper' => ['Neema Swai', 'neema@watercom.test', User::ROLE_STOREKEEPER, 'Storekeeper', 'WC-0170'],
            'manager' => ['Peter Lema', 'peter@watercom.test', User::ROLE_WAREHOUSE_MANAGER, 'Warehouse Manager', 'WC-0171'],
            'accountant' => ['Grace Mushi', 'grace@watercom.test', User::ROLE_ACCOUNTANT, 'Accountant', 'WC-0172'],
            'sales' => ['Hassan Juma', 'hassan@watercom.test', User::ROLE_SALES, 'Sales Executive', 'WC-0173'],
            'procurement' => ['Upendo Kimaro', 'upendo@watercom.test', User::ROLE_PROCUREMENT, 'Procurement Officer', 'WC-0174'],
        ];

        $people = [];

        foreach ($rows as $key => [$name, $email, $role, $title, $code]) {
            $people[$key] = User::updateOrCreate(['email' => $email], [
                'company_id' => $company->id, 'name' => $name, 'password' => 'Password123!',
                'role' => $role, 'job_title' => $title, 'employee_code' => $code,
                'status' => 'active', 'locale' => 'en', 'email_verified_at' => now(),
            ]);
        }

        return $people;
    }

    /** @return array<string, Warehouse> */
    private function places(Company $company): array
    {
        $main = Warehouse::query()->where('code', 'MAIN')->firstOrFail();
        $main->update(['name' => 'Factory store Mbezi', 'branch' => 'Dar es Salaam']);

        return [
            'main' => $main,
            'finished' => Warehouse::firstOrCreate(['code' => 'FGW'], ['company_id' => $company->id, 'name' => 'Finished goods warehouse', 'type' => 'warehouse', 'branch' => 'Dar es Salaam']),
            'arusha' => Warehouse::firstOrCreate(['code' => 'ARU'], ['company_id' => $company->id, 'name' => 'Arusha depot', 'type' => 'depot', 'branch' => 'Arusha']),
        ];
    }

    /** @return array<string, Product> */
    private function products(Company $company): array
    {
        $unit = fn (string $code) => Unit::query()->where('code', $code)->value('id');
        $category = fn (string $name) => ProductCategory::query()->where('name', $name)->value('id');

        $rows = [
            'preform' => ['RM-PRF-28', 'PET preform 28g', 'raw_material', 'Preforms & caps', 'PCS', 95, 0, 20000, true, false],
            'cap' => ['RM-CAP-28', 'Bottle cap 28mm', 'raw_material', 'Preforms & caps', 'PCS', 18, 0, 20000, true, false],
            'label' => ['PK-LBL-500', 'Label: 500ml', 'packaging', 'Labels & packaging', 'PCS', 12, 0, 20000, false, false],
            'shrink' => ['PK-SHR-24', 'Shrink film (24-pack)', 'packaging', 'Labels & packaging', 'KG', 5200, 0, 200, false, false],
            'w500' => ['FG-W500-24', 'Watercom 500ml × 24', 'finished_good', 'Bottled water', 'CTN', 5400, 8500, 300, true, true],
            'w1500' => ['FG-W1500-12', 'Watercom 1.5L × 12', 'finished_good', 'Bottled water', 'CTN', 6800, 10500, 200, true, true],
            'w19' => ['FG-W19L', 'Watercom 19L dispenser jar', 'finished_good', 'Bottled water', 'PCS', 3500, 6000, 80, true, true],
        ];

        $products = [];

        foreach ($rows as $key => [$sku, $name, $type, $cat, $u, $cost, $price, $reorder, $batches, $expiry]) {
            $products[$key] = Product::firstOrCreate(['sku' => $sku], [
                'company_id' => $company->id, 'name' => $name, 'type' => $type,
                'category_id' => $category($cat), 'unit_id' => $unit($u),
                'cost_price' => $cost, 'sale_price' => $price, 'reorder_level' => $reorder,
                'track_batches' => $batches, 'track_expiry' => $expiry,
                'custom_fields' => $type === 'finished_good' ? ['pack_size' => explode(' ', $name, 2)[1]] : null,
            ]);
        }

        return $products;
    }

    /** @return array<string, Supplier> */
    private function suppliers(Company $company): array
    {
        $rows = [
            'pet' => ['SUP-0001', 'East Africa PET Industries', 'Raw materials', 'Mwanaisha Ally', '+255 754 210 300', 30, 'CRDB Bank', '0150 2233 4401'],
            'pack' => ['SUP-0002', 'Dar Packaging Solutions', 'Packaging', 'Kelvin Mbwambo', '+255 713 440 912', 14, 'NMB Bank', '2041 7781 120'],
            'tyres' => ['SUP-0003', 'Mlimani Tyre Centre', 'Fleet', 'Rashid Omari', '+255 784 600 155', 7, 'NBC Bank', '0110 4455 891'],
        ];

        $suppliers = [];

        foreach ($rows as $key => [$code, $name, $cat, $contact, $phone, $terms, $bank, $acct]) {
            $suppliers[$key] = Supplier::firstOrCreate(['code' => $code], [
                'company_id' => $company->id, 'name' => $name, 'category' => $cat,
                'contact_person' => $contact, 'phone' => $phone, 'payment_terms_days' => $terms,
                'bank_name' => $bank, 'bank_account_name' => $name, 'bank_account_number' => $acct, 'city' => 'Dar es Salaam',
            ]);
        }

        return $suppliers;
    }

    private function customers(Company $company): void
    {
        $rows = [
            ['CUS-0001', 'Shoppers Supermarket: Masaki', 'Supermarkets', 15000000, 30, false],
            ['CUS-0002', 'Kariakoo Wholesalers Ltd', 'Wholesale', 25000000, 14, false],
            ['CUS-0003', 'Mama Ntilie Kiosk Network', 'Retail', 0, 0, true],
            ['CUS-0004', 'Serena Hotel Dar es Salaam', 'Hospitality', 8000000, 30, false],
            ['CUS-0005', 'Arusha Distributors', 'Distributors', 20000000, 21, false],
        ];

        foreach ($rows as [$code, $name, $group, $limit, $terms, $prepay]) {
            Customer::firstOrCreate(['code' => $code], [
                'company_id' => $company->id, 'name' => $name, 'customer_group' => $group,
                'credit_limit' => $limit, 'payment_terms_days' => $terms, 'requires_prepayment' => $prepay,
                'city' => str_contains($name, 'Arusha') ? 'Arusha' : 'Dar es Salaam',
            ]);
        }
    }

    /** A month of stock life: opening balances, receipts, a transfer, an issue, and a draft waiting to post. */
    private function history(array $places, array $products, array $suppliers, array $staff): void
    {
        $batch = 'WC'.now()->subDays(20)->format('ymd');
        $expiry = now()->addMonths(11)->toDateString();
        $prepare = $staff['storekeeper'];
        $post = $staff['manager'];

        $make = function (string $type, array $header, array $lines, bool $posted = true) use ($prepare, $post) {
            $document = $this->documents->create($type, $header, $lines, $prepare);

            return $posted ? $this->documents->post($document, $post) : $document;
        };

        $make('opening', ['warehouse_id' => $places['main']->id, 'document_date' => now()->subDays(28)->toDateString(), 'reason' => 'Balances at go-live'], [
            ['product_id' => $products['preform']->id, 'quantity' => 60000, 'unit_cost' => 95, 'batch_number' => 'PRF-2409'],
            ['product_id' => $products['cap']->id, 'quantity' => 60000, 'unit_cost' => 18, 'batch_number' => 'CAP-2409'],
            ['product_id' => $products['label']->id, 'quantity' => 45000, 'unit_cost' => 12],
            ['product_id' => $products['shrink']->id, 'quantity' => 650, 'unit_cost' => 5200],
        ]);

        $make('opening', ['warehouse_id' => $places['finished']->id, 'document_date' => now()->subDays(28)->toDateString(), 'reason' => 'Balances at go-live'], [
            ['product_id' => $products['w500']->id, 'quantity' => 1800, 'unit_cost' => 5400, 'batch_number' => $batch, 'expiry_date' => $expiry],
            ['product_id' => $products['w1500']->id, 'quantity' => 950, 'unit_cost' => 6800, 'batch_number' => $batch, 'expiry_date' => $expiry],
            ['product_id' => $products['w19']->id, 'quantity' => 60, 'unit_cost' => 3500, 'batch_number' => $batch, 'expiry_date' => $expiry],
        ]);

        $make('grn', ['warehouse_id' => $places['main']->id, 'supplier_id' => $suppliers['pet']->id, 'reference' => 'DN-EAPI-7731', 'document_date' => now()->subDays(12)->toDateString()], [
            ['product_id' => $products['preform']->id, 'quantity' => 40000, 'unit_cost' => 98, 'batch_number' => 'PRF-2410'],
        ]);

        $make('grn', ['warehouse_id' => $places['main']->id, 'supplier_id' => $suppliers['pack']->id, 'reference' => 'DPS-INV-0442', 'document_date' => now()->subDays(9)->toDateString()], [
            ['product_id' => $products['label']->id, 'quantity' => 30000, 'unit_cost' => 11.5],
            ['product_id' => $products['shrink']->id, 'quantity' => 300, 'unit_cost' => 5350],
        ]);

        $make('transfer', ['warehouse_id' => $places['finished']->id, 'to_warehouse_id' => $places['arusha']->id, 'reference' => 'LO-ARU-0193', 'document_date' => now()->subDays(6)->toDateString(), 'reason' => 'Depot replenishment'], [
            ['product_id' => $products['w500']->id, 'quantity' => 600, 'batch_number' => $batch],
            ['product_id' => $products['w1500']->id, 'quantity' => 300, 'batch_number' => $batch],
        ]);

        $make('issue', ['warehouse_id' => $places['main']->id, 'document_date' => now()->subDays(3)->toDateString(), 'reason' => 'Line 2 production run'], [
            ['product_id' => $products['preform']->id, 'quantity' => 24000, 'batch_number' => 'PRF-2409'],
            ['product_id' => $products['cap']->id, 'quantity' => 24000, 'batch_number' => 'CAP-2409'],
            ['product_id' => $products['label']->id, 'quantity' => 24000],
            ['product_id' => $products['shrink']->id, 'quantity' => 85],
        ]);

        $make('adjustment', ['warehouse_id' => $places['finished']->id, 'document_date' => now()->subDays(1)->toDateString(), 'reason' => 'Cartons crushed during loading'], [
            ['product_id' => $products['w500']->id, 'quantity' => -12, 'batch_number' => $batch],
        ]);

        // Left for the warehouse manager to review and post in the demo.
        $make('grn', ['warehouse_id' => $places['main']->id, 'supplier_id' => $suppliers['pet']->id, 'reference' => 'DN-EAPI-7790'], [
            ['product_id' => $products['cap']->id, 'quantity' => 50000, 'unit_cost' => 17.5, 'batch_number' => 'CAP-2411'],
        ], false);
    }
}
