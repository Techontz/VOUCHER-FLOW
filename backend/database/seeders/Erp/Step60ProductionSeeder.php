<?php

namespace Database\Seeders\Erp;

use App\Models\Company;
use App\Models\Erp\Product;
use App\Models\Erp\ProductCategory;
use App\Models\Erp\Production\Bom;
use App\Models\Erp\Production\ProductionOrder;
use App\Models\Erp\Production\ProductionReceipt;
use App\Models\Erp\Production\QcCheck;
use App\Models\Erp\Production\WorkCentre;
use App\Models\Erp\Supplier;
use App\Models\Erp\Unit;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Services\Erp\Production\Boms;
use App\Services\Erp\Production\ProductionOrders;
use App\Services\Erp\StockDocuments;
use App\Support\TenantContext;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;

/**
 * Watercom's bottling floor: two lines, bills of materials for the 500ml and
 * 1.5L cartons, and a month of production orders in every status, with real
 * material issues, output, quality checks (one batch rejected for cap
 * torque) and closed orders whose variance reached the ledger.
 *
 * Idempotent: people, products, work centres and bills of materials are
 * matched on their natural keys; the order history is written only when the
 * company has no production orders yet.
 */
class Step60ProductionSeeder extends Seeder
{
    public function __construct(
        private readonly Boms $boms,
        private readonly ProductionOrders $orders,
        private readonly StockDocuments $documents,
    ) {}

    public function run(): void
    {
        $company = app(TenantContext::class)->company();

        if (! $company) {
            return;
        }

        $modules = is_array($company->modules) ? $company->modules : [];

        if (! in_array('production', $modules, true)) {
            $company->forceFill(['modules' => [...$modules, 'production']])->save();
        }

        $people = $this->people($company);
        $products = $this->products($company);
        $centres = $this->workCentres($company);
        $boms = $this->billsOfMaterials($products, $centres, $people['manager']);

        if (! ProductionOrder::query()->exists()) {
            $this->materials($company, $products, $people);
            $this->history($products, $boms, $people);
        }
    }

    /** @return array<string, User> */
    private function people(Company $company): array
    {
        $rows = [
            'manager' => ['Zuberi Mwakyusa', 'zuberi@watercom.test', 'Production Manager', 'WC-0260'],
            'quality' => ['Salome Kisanga', 'salome@watercom.test', 'Quality Controller', 'WC-0261'],
        ];

        $people = [];

        foreach ($rows as $key => [$name, $email, $title, $code]) {
            $people[$key] = User::query()->where('email', $email)->first() ?? User::create([
                'company_id' => $company->id, 'name' => $name, 'email' => $email, 'password' => 'Password123!',
                'role' => User::ROLE_PRODUCTION_MANAGER, 'job_title' => $title, 'employee_code' => $code,
                'status' => 'active', 'locale' => 'en', 'email_verified_at' => now(),
            ]);
        }

        $people['storekeeper'] = User::query()->where('email', 'neema@watercom.test')->first() ?? $people['manager'];
        $people['accountant'] = User::query()->where('email', 'grace@watercom.test')->first() ?? $people['manager'];

        return $people;
    }

    /** @return array<string, Product> */
    private function products(Company $company): array
    {
        $unit = fn (string $code) => Unit::query()->where('code', $code)->value('id') ?? Unit::query()->value('id');
        $category = fn (string $name) => ProductCategory::query()->where('name', $name)->value('id');

        $rows = [
            'preform' => ['RM-PRF-28', 'PET preform 28g', 'raw_material', 'Preforms & caps', 'PCS', 95, 0, true, false],
            'preform38' => ['RM-PRF-38', 'PET preform 38g (1.5L)', 'raw_material', 'Preforms & caps', 'PCS', 148, 0, true, false],
            'cap' => ['RM-CAP-28', 'Bottle cap 28mm', 'raw_material', 'Preforms & caps', 'PCS', 18, 0, true, false],
            'label' => ['PK-LBL-500', 'Label: 500ml', 'packaging', 'Labels & packaging', 'PCS', 12, 0, false, false],
            'label1500' => ['PK-LBL-1500', 'Label: 1.5L', 'packaging', 'Labels & packaging', 'PCS', 15, 0, false, false],
            'shrink' => ['PK-SHR-24', 'Shrink film (24-pack)', 'packaging', 'Labels & packaging', 'KG', 5200, 0, false, false],
            'w500' => ['FG-W500-24', 'Watercom 500ml × 24', 'finished_good', 'Bottled water', 'CTN', 5400, 8500, true, true],
            'w1500' => ['FG-W1500-12', 'Watercom 1.5L × 12', 'finished_good', 'Bottled water', 'CTN', 6800, 10500, true, true],
        ];

        $products = [];

        foreach ($rows as $key => [$sku, $name, $type, $cat, $u, $cost, $price, $batches, $expiry]) {
            $products[$key] = Product::query()->where('sku', $sku)->first() ?? Product::create([
                'company_id' => $company->id, 'sku' => $sku, 'name' => $name, 'type' => $type,
                'category_id' => $category($cat), 'unit_id' => $unit($u),
                'cost_price' => $cost, 'sale_price' => $price, 'reorder_level' => $type === 'finished_good' ? 200 : 10000,
                'track_batches' => $batches, 'track_expiry' => $expiry,
            ]);
        }

        return $products;
    }

    /** @return array<string, WorkCentre> */
    private function workCentres(Company $company): array
    {
        $rows = [
            'line1' => ['LINE-1', 'Line 1: 500ml blow, fill and cap', 'Krones combi block, 12,000 bottles an hour, Mbezi factory.', 500, 45000],
            'line2' => ['LINE-2', 'Line 2: 1.5L blow, fill and cap', 'Semi-automatic line for 1.5L bottles, Mbezi factory.', 250, 38000],
            'pack' => ['PACK-1', 'Shrink wrapping and palletising', 'Shrink tunnel and manual palletising for both lines.', 800, 15000],
        ];

        $centres = [];

        foreach ($rows as $key => [$code, $name, $description, $capacity, $hourly]) {
            $centres[$key] = WorkCentre::query()->where('code', $code)->first() ?? WorkCentre::create([
                'company_id' => $company->id, 'code' => $code, 'name' => $name, 'description' => $description,
                'capacity_per_hour' => $capacity, 'hourly_cost' => $hourly,
            ]);
        }

        return $centres;
    }

    /** @return array<string, Bom> */
    private function billsOfMaterials(array $products, array $centres, User $actor): array
    {
        $boms = [];

        if (! Bom::query()->where('product_id', $products['w500']->id)->exists()) {
            // The first recipe, before the lighter shrink film spec, kept as history.
            $this->boms->create([
                'product_id' => $products['w500']->id, 'name' => 'Watercom 500ml × 24 v1', 'output_quantity' => 100,
                'work_centre_id' => $centres['line1']->id, 'labour_cost' => 16000, 'overhead_cost' => 12000,
                'notes' => 'Original recipe with 2.2 kg of shrink film per 100 cartons.',
            ], [
                ['product_id' => $products['preform']->id, 'quantity' => 2400, 'scrap_percent' => 2],
                ['product_id' => $products['cap']->id, 'quantity' => 2400, 'scrap_percent' => 1],
                ['product_id' => $products['label']->id, 'quantity' => 2400, 'scrap_percent' => 2],
                ['product_id' => $products['shrink']->id, 'quantity' => 2.2, 'scrap_percent' => 3],
            ], $actor);

            $current = $this->boms->create([
                'product_id' => $products['w500']->id, 'name' => 'Watercom 500ml × 24 v2', 'output_quantity' => 100,
                'work_centre_id' => $centres['line1']->id, 'labour_cost' => 18000, 'overhead_cost' => 12000,
                'notes' => '24 bottles per carton, 1.8 kg of 40 micron shrink film per 100 cartons.',
            ], [
                ['product_id' => $products['preform']->id, 'quantity' => 2400, 'scrap_percent' => 1.5],
                ['product_id' => $products['cap']->id, 'quantity' => 2400, 'scrap_percent' => 1],
                ['product_id' => $products['label']->id, 'quantity' => 2400, 'scrap_percent' => 2],
                ['product_id' => $products['shrink']->id, 'quantity' => 1.8, 'scrap_percent' => 3],
            ], $actor);

            $this->boms->activate($current, $actor);
        }

        if (! Bom::query()->where('product_id', $products['w1500']->id)->exists()) {
            $this->boms->create([
                'product_id' => $products['w1500']->id, 'name' => 'Watercom 1.5L × 12 v1', 'output_quantity' => 100,
                'work_centre_id' => $centres['line2']->id, 'labour_cost' => 15000, 'overhead_cost' => 10000,
                'notes' => '12 bottles per carton, 1.2 kg of shrink film per 100 cartons.',
            ], [
                ['product_id' => $products['preform38']->id, 'quantity' => 1200, 'scrap_percent' => 1.5],
                ['product_id' => $products['cap']->id, 'quantity' => 1200, 'scrap_percent' => 1],
                ['product_id' => $products['label1500']->id, 'quantity' => 1200, 'scrap_percent' => 2],
                ['product_id' => $products['shrink']->id, 'quantity' => 1.2, 'scrap_percent' => 3],
            ], $actor);
        }

        $boms['w500'] = Bom::query()->where('product_id', $products['w500']->id)->where('is_active', true)->firstOrFail();
        $boms['w1500'] = Bom::query()->where('product_id', $products['w1500']->id)->where('is_active', true)->firstOrFail();

        return $boms;
    }

    /** Enough material on the shelf for a month of runs: go-live stock for the 1.5L line and fresh deliveries. */
    private function materials(Company $company, array $products, array $people): void
    {
        $main = Warehouse::query()->where('code', 'MAIN')->firstOrFail();
        $pet = Supplier::query()->where('code', 'SUP-0001')->first();
        $pack = Supplier::query()->where('code', 'SUP-0002')->first();
        $manager = User::query()->where('email', 'peter@watercom.test')->first() ?? $people['manager'];

        $post = function (string $type, array $header, array $lines) use ($people, $manager) {
            $this->documents->post($this->documents->create($type, $header, $lines, $people['storekeeper']), $manager);
        };

        $post('opening', ['warehouse_id' => $main->id, 'document_date' => now()->subDays(28)->toDateString(), 'reason' => 'Balances at go-live: 1.5L line materials'], [
            ['product_id' => $products['preform38']->id, 'quantity' => 30000, 'unit_cost' => 148, 'batch_number' => 'PRF38-2409'],
            ['product_id' => $products['label1500']->id, 'quantity' => 30000, 'unit_cost' => 15],
        ]);

        $post('grn', ['warehouse_id' => $main->id, 'supplier_id' => $pet?->id, 'reference' => 'DN-EAPI-7744', 'document_date' => now()->subDays(20)->toDateString()], [
            ['product_id' => $products['cap']->id, 'quantity' => 90000, 'unit_cost' => 17.8, 'batch_number' => 'CAP-2410'],
            ['product_id' => $products['preform']->id, 'quantity' => 30000, 'unit_cost' => 97, 'batch_number' => 'PRF-2410B'],
        ]);

        $post('grn', ['warehouse_id' => $main->id, 'supplier_id' => $pack?->id, 'reference' => 'DPS-INV-0451', 'document_date' => now()->subDays(16)->toDateString()], [
            ['product_id' => $products['label']->id, 'quantity' => 40000, 'unit_cost' => 11.8],
            ['product_id' => $products['shrink']->id, 'quantity' => 200, 'unit_cost' => 5300],
        ]);
    }

    /** A month on the floor, oldest first, so every order sees the stock the ones before it left. */
    private function history(array $products, array $boms, array $people): void
    {
        $main = Warehouse::query()->where('code', 'MAIN')->firstOrFail();
        $finished = Warehouse::query()->where('code', 'FGW')->first() ?? $main;

        $plan = function (string $key, float $quantity, int $startsIn, int $days, ?string $reference = null) use ($products, $boms, $main, $finished, $people) {
            $start = now()->addDays($startsIn)->toDateString();

            $order = $this->orders->create([
                'product_id' => $products[$key]->id, 'bom_id' => $boms[$key]->id, 'planned_quantity' => $quantity,
                'materials_warehouse_id' => $main->id, 'output_warehouse_id' => $finished->id,
                'planned_start' => $start, 'planned_end' => now()->addDays($startsIn + $days)->toDateString(),
                'reference' => $reference,
            ], $people['manager']);
            $order->forceFill(['created_at' => Carbon::parse($start)->subDays(2)->setTime(9, 0)])->save();

            return $order;
        };

        $release = function (ProductionOrder $order, int $daysAgo) use ($people) {
            $order = $this->orders->release($order, $people['manager']);
            $order->forceFill(['released_at' => now()->subDays($daysAgo)->setTime(7, 30)])->save();

            return $order;
        };

        // Issues the BOM requirement (with its allowance), plus any extra per component.
        $issue = function (ProductionOrder $order, int $daysAgo, float $share = 1.0, array $extra = []) use ($people) {
            $lines = [];

            foreach ($this->orders->requirements($order->fresh()) as $row) {
                $quantity = $row['required_quantity'] * $share + ($extra[$row['product_id']] ?? 0);
                $quantity = $row['product']['sku'] === 'PK-SHR-24' ? round($quantity, 1) : ceil($quantity);

                if ($quantity > 0) {
                    $lines[] = ['product_id' => $row['product_id'], 'quantity' => $quantity];
                }
            }

            $this->orders->issue($order->fresh(), $lines, $people['storekeeper'], now()->subDays($daysAgo)->toDateString());
            $fresh = $order->fresh();
            $when = now()->subDays($daysAgo)->setTime(8, 0);

            if (! $fresh->started_at || $fresh->started_at->gt($when)) {
                $fresh->forceFill(['started_at' => $when])->save();
            }
        };

        $receive = function (ProductionOrder $order, int $daysAgo, float $good, float $rejected, float $wastage, bool $final, string $suffix = 'A') use ($people) {
            $date = now()->subDays($daysAgo);
            $prefix = str_contains($order->product->sku, '1500') ? 'W15' : 'W500';

            return $this->orders->receive($order->fresh(), [
                'receipt_date' => $date->toDateString(),
                'produced_quantity' => $good + $rejected + $wastage,
                'good_quantity' => $good, 'rejected_quantity' => $rejected, 'wastage_quantity' => $wastage,
                'batch_number' => $prefix.'-'.$date->format('ymd').'-'.$suffix,
                'expiry_date' => $date->copy()->addYear()->toDateString(),
                'is_final' => $final,
                'notes' => $rejected > 0 ? 'Rejects: short fills and crushed bottles at the labeller.' : null,
            ], $people['storekeeper']);
        };

        $qc = function (ProductionReceipt $receipt, bool $pass, int $daysAgo) use ($people) {
            $parameters = [
                ['name' => 'pH', 'target' => '6.5 to 8.5', 'value' => (string) (7.0 + ($receipt->id % 5) / 10), 'passed' => true],
                ['name' => 'Total dissolved solids', 'target' => 'up to 500 mg/L', 'value' => (string) (110 + $receipt->id % 30).' mg/L', 'passed' => true],
                ['name' => 'Residual chlorine', 'target' => 'Nil', 'value' => 'Nil', 'passed' => true],
                ['name' => 'Fill level', 'target' => '500 ml plus or minus 5', 'value' => $pass ? '501 ml' : '497 ml', 'passed' => true],
                ['name' => 'Cap torque', 'target' => '12 to 18 in-lb', 'value' => $pass ? '15 in-lb' : '8 in-lb', 'passed' => $pass],
                ['name' => 'Label and coding', 'target' => 'Batch and expiry legible', 'value' => 'Legible', 'passed' => true],
            ];

            $check = $this->orders->inspect($receipt->fresh(), $pass ? QcCheck::RELEASE : QcCheck::REJECT, $parameters, $people['quality'],
                $pass ? 'Released to the finished goods warehouse.' : 'Loose caps on the sample; batch quarantined and sent back for rework.');
            $check->forceFill(['checked_at' => now()->subDays($daysAgo)->setTime(16, 0)])->save();
        };

        $close = function (ProductionOrder $order, int $daysAgo) use ($people) {
            $order = $this->orders->close($order->fresh(), $people['accountant']);
            $order->forceFill(['closed_at' => now()->subDays($daysAgo)->setTime(17, 0)])->save();
        };

        $settle = function (ProductionOrder $order, int $daysAgo) {
            $order->fresh()->forceFill(['completed_at' => now()->subDays($daysAgo)->setTime(17, 30)])->save();
        };

        // Closed: three runs from the start of the month.
        $o1 = $plan('w500', 600, -26, 1, 'Shoppers Masaki restock');
        $release($o1, 26);
        $issue($o1, 26);
        $qc($receive($o1, 25, 594, 3, 3, true), true, 25);
        $settle($o1, 25);
        $close($o1, 24);

        $o2 = $plan('w1500', 300, -22, 1, 'Serena Hotel monthly order');
        $release($o2, 22);
        $issue($o2, 22);
        $qc($receive($o2, 21, 296, 2, 2, true), true, 21);
        $settle($o2, 21);
        $close($o2, 20);

        $o3 = $plan('w500', 500, -18, 1, 'Kariakoo Wholesalers');
        $release($o3, 18);
        $issue($o3, 18);
        // The labeller jammed: 300 more labels went to the line than the recipe allows.
        $issue($o3, 17, 0, [$products['label']->id => 300]);
        $qc($receive($o3, 17, 488, 7, 5, true), true, 17);
        $settle($o3, 17);
        $close($o3, 16);

        // Cancelled before anything was issued.
        $o4 = $plan('w1500', 250, -15, 1, 'Arusha depot top-up');
        $release($o4, 16);
        $this->orders->cancel($o4->fresh(), 'Line 2 down for planned maintenance; volume moved to next week.', $people['manager']);

        // Completed, waiting for finance to close it.
        $o5 = $plan('w500', 500, -12, 1, 'Arusha Distributors');
        $release($o5, 12);
        $issue($o5, 12);
        $qc($receive($o5, 11, 492, 4, 4, true), true, 11);
        $settle($o5, 11);

        // Completed with a rejected batch: the first 100 cartons failed cap torque.
        $o6 = $plan('w1500', 300, -9, 2, 'Depot stock build');
        $release($o6, 9);
        $issue($o6, 9);
        $qc($receive($o6, 8, 98, 1, 1, false, 'A'), false, 8);
        $qc($receive($o6, 7, 194, 2, 4, true, 'B'), true, 7);
        $settle($o6, 7);

        // In progress: a long 500ml run with output today, one batch still at QC.
        $o7 = $plan('w500', 800, -3, 4, 'Festive season stock');
        $release($o7, 3);
        $issue($o7, 3, 0.6);
        $qc($receive($o7, 2, 296, 2, 2, false, 'A'), true, 2);
        $issue($o7, 1, 0.4);
        $qc($receive($o7, 0, 247, 2, 1, false, 'A'), true, 0);
        $receive($o7, 0, 148, 1, 1, false, 'B');

        // In progress: 1.5L materials on the line, nothing off it yet.
        $o8 = $plan('w1500', 300, 0, 1, 'Mama Ntilie kiosks');
        $release($o8, 0);
        $issue($o8, 0);

        // Released and waiting for the line; planned for later in the week.
        $o9 = $plan('w500', 500, 1, 1, 'Shoppers Masaki restock');
        $release($o9, 0);
        $plan('w500', 700, 3, 2, 'Kariakoo Wholesalers');
        $plan('w1500', 400, 5, 1, 'Serena Hotel monthly order');
    }
}
