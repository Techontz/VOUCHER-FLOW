<?php

namespace Database\Seeders\Erp;

use App\Models\Company;
use App\Models\Erp\Account;
use App\Models\Erp\Customer;
use App\Models\Erp\Product;
use App\Models\Erp\Sales\LoadingOrder;
use App\Models\Erp\Sales\PriceList;
use App\Models\Erp\Sales\SalesOrder;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Services\Erp\Sales\Dispatch;
use App\Services\Erp\Sales\SalesCreditNotes;
use App\Services\Erp\Sales\SalesInvoices;
use App\Services\Erp\Sales\SalesOrders;
use App\Services\Erp\Sales\SalesReceipts;
use App\Support\TenantContext;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

/**
 * Watercom's sales and dispatch, through the real services: price lists,
 * quotations in every state, orders from draft to delivered, a prepayment
 * order waiting for finance to verify its payment, a verified one on the
 * loading bay, deliveries with proof of delivery, one short delivery waiting
 * for a decision, and invoices old enough to fill every aged-receivables
 * bucket.
 *
 * Re-runnable: people, customers and price lists are matched on natural keys,
 * and the documents are written only into a company that has no sales orders.
 */
class Step20SalesSeeder extends Seeder
{
    public function __construct(
        private readonly SalesOrders $orders,
        private readonly SalesInvoices $invoices,
        private readonly SalesReceipts $receipts,
        private readonly SalesCreditNotes $credits,
        private readonly Dispatch $dispatch,
    ) {}

    public function run(): void
    {
        /** @var Company $company */
        $company = app(TenantContext::class)->company();

        $modules = is_array($company->modules) ? $company->modules : [];
        $missing = array_diff(['sales', 'dispatch'], $modules);
        if ($missing) {
            $company->forceFill(['modules' => array_values([...$modules, ...$missing])])->save();
        }

        $people = $this->people($company);
        $customers = $this->customers($company);
        $products = Product::query()->whereIn('sku', ['FG-W500-24', 'FG-W1500-12', 'FG-W19L'])->get()->keyBy('sku');

        if ($products->count() < 3) {
            return;
        }

        $this->priceLists($company, $products, $customers, $people['finance']);

        if (SalesOrder::query()->exists()) {
            return;
        }

        $this->documents($people, $customers, $products);
    }

    /** @return array<string, User> */
    private function people(Company $company): array
    {
        $make = fn (string $email, string $name, string $role, string $title, string $code) => User::updateOrCreate(['email' => $email], [
            'company_id' => $company->id, 'name' => $name, 'password' => 'Password123!', 'role' => $role,
            'job_title' => $title, 'employee_code' => $code, 'status' => 'active', 'locale' => 'en', 'email_verified_at' => now(),
        ]);
        $find = fn (string $email) => User::query()->where('email', $email)->first();

        $finance = $make('faraji@watercom.test', 'Faraji Mrisho', User::ROLE_FINANCE, 'Finance Manager', 'WC-0180');
        $dispatch = $make('baraka@watercom.test', 'Baraka Mollel', User::ROLE_DISPATCH, 'Dispatch Officer', 'WC-0181');

        return [
            'finance' => $finance,
            'dispatch' => $dispatch,
            'sales' => $find('hassan@watercom.test') ?? $finance,
            'accountant' => $find('grace@watercom.test') ?? $finance,
            'cashier' => $find('mwajuma@watercom.test') ?? $finance,
            'store' => $find('neema@watercom.test') ?? $dispatch,
            'manager' => $find('peter@watercom.test') ?? $dispatch,
        ];
    }

    /** @return array<string, Customer> */
    private function customers(Company $company): array
    {
        $extra = [
            ['CUS-0101', 'Mwanza Lake Traders', 'Distributors', 0, 0, true, 'Mwanza', 'Kenyatta Road, Mwanza', 'Paulo Masanja', '+255 767 330 418'],
            ['CUS-0102', 'Dodoma Fresh Mart', 'Supermarkets', 5000000, 14, false, 'Dodoma', 'Nyerere Square, Dodoma', 'Zawadi Chande', '+255 715 902 117'],
        ];

        foreach ($extra as [$code, $name, $group, $limit, $terms, $prepay, $city, $address, $contact, $phone]) {
            Customer::firstOrCreate(['code' => $code], [
                'company_id' => $company->id, 'name' => $name, 'customer_group' => $group, 'credit_limit' => $limit,
                'payment_terms_days' => $terms, 'requires_prepayment' => $prepay, 'city' => $city, 'address' => $address,
                'contact_person' => $contact, 'phone' => $phone,
            ]);
        }

        $codes = ['shoppers' => 'CUS-0001', 'kariakoo' => 'CUS-0002', 'mama' => 'CUS-0003', 'serena' => 'CUS-0004', 'arusha' => 'CUS-0005', 'mwanza' => 'CUS-0101', 'dodoma' => 'CUS-0102'];

        return array_filter(array_map(fn ($code) => Customer::query()->where('code', $code)->first(), $codes));
    }

    private function priceLists(Company $company, $products, array $customers, User $actor): void
    {
        $lists = [
            'STANDARD' => ['Standard prices', true, [8500, 10500, 6000], null],
            'WHOLESALE' => ['Wholesale and distributors', false, [8000, 9900, 5600], ['kariakoo', 'arusha', 'mwanza']],
            'HORECA' => ['Hotels, restaurants and cafes', false, [8800, 10900, 6200], ['serena']],
        ];
        $skus = ['FG-W500-24', 'FG-W1500-12', 'FG-W19L'];

        foreach ($lists as $code => [$name, $default, $prices, $who]) {
            $list = PriceList::query()->where('code', $code)->first();

            if (! $list) {
                $list = PriceList::create(['company_id' => $company->id, 'code' => $code, 'name' => $name, 'is_default' => $default, 'created_by' => $actor->id]);
                foreach ($skus as $i => $sku) {
                    $list->items()->create([
                        'company_id' => $company->id, 'product_id' => $products[$sku]->id, 'unit_price' => $prices[$i],
                        'effective_from' => now()->subMonths(3)->startOfMonth()->toDateString(),
                    ]);
                }
                if ($code === 'STANDARD') {
                    // The announced price rise, so the list shows a dated change.
                    $list->items()->create([
                        'company_id' => $company->id, 'product_id' => $products['FG-W500-24']->id, 'unit_price' => 8900,
                        'effective_from' => now()->addDays(14)->toDateString(),
                    ]);
                }
            }

            foreach ($who ?? [] as $key) {
                if (isset($customers[$key]) && ! $customers[$key]->price_list) {
                    $customers[$key]->update(['price_list' => $code]);
                }
            }
        }
    }

    private function documents(array $p, array $c, $products): void
    {
        $fg = Warehouse::query()->where('code', 'FGW')->first() ?? Warehouse::query()->where('code', 'MAIN')->firstOrFail();
        $aru = Warehouse::query()->where('code', 'ARU')->first() ?? $fg;
        $bank = Account::query()->where('system_key', 'bank')->first()
            ?? Account::query()->where('type', 'asset')->whereBetween(DB::raw('CAST(code AS UNSIGNED)'), [1100, 1299])->firstOrFail();
        $cash = Account::query()->where('system_key', 'cash')->first() ?? $bank;
        $w500 = $products['FG-W500-24']->id;
        $w1500 = $products['FG-W1500-12']->id;
        $w19 = $products['FG-W19L']->id;
        $line = fn (int $product, float $qty) => ['product_id' => $product, 'quantity' => $qty];

        /* ── quotations ─────────────────────────────────────────────── */
        $this->orders->saveQuotation(null, ['customer_id' => $c['dodoma']->id, 'notes' => 'Opening order for the new Dodoma branch.'], [$line($w500, 120), $line($w1500, 60)], $p['sales']);
        $sent = $this->orders->saveQuotation(null, ['customer_id' => $c['serena']->id, 'notes' => 'Conference season, July to September.'], [$line($w500, 200), $line($w19, 40)], $p['sales']);
        $this->orders->setQuotationStatus($sent, 'sent', $p['sales']);
        $declined = $this->orders->saveQuotation(null, ['customer_id' => $c['shoppers']->id, 'quote_date' => now()->subDays(20)->toDateString()], [$line($w1500, 300)], $p['sales']);
        $this->orders->setQuotationStatus($declined, 'rejected', $p['sales']);
        $accepted = $this->orders->saveQuotation(null, ['customer_id' => $c['kariakoo']->id], [$line($w500, 150)], $p['sales']);
        $this->orders->setQuotationStatus($accepted, 'sent', $p['sales']);
        $this->orders->convert($accepted, $p['sales']); // stays a draft order

        /* ── orders: approve everything first, while no invoice is overdue ── */
        $make = function (string $customer, array $lines, ?string $approve = 'approve', array $extra = []) use ($c, $p) {
            $order = $this->orders->saveOrder(null, ['customer_id' => $c[$customer]->id, ...$extra], $lines, $p['sales']);
            if ($approve === null) {
                return $order;
            }
            $order = $this->orders->submit($order, $p['sales']);

            return match ($approve) {
                'approve' => $this->orders->approve($order, $p['finance']),
                'reject' => $this->orders->reject($order, 'Customer asked us to hold until their new menu is printed.', $p['finance']),
                'cancel' => $this->orders->cancel($order, $p['finance']),
                default => $order,
            };
        };

        $make('dodoma', [$line($w500, 80)], 'submit');
        $make('serena', [$line($w19, 30)], 'reject');
        $make('arusha', [$line($w1500, 100)], 'cancel');

        $mamaPending = $make('mama', [$line($w500, 25), $line($w19, 10)]);      // receipt recorded, waiting for verification
        $mwanzaUnpaid = $make('mwanza', [$line($w500, 60)]);                     // invoice issued, nothing paid
        $mwanzaLoading = $make('mwanza', [$line($w500, 90), $line($w1500, 40)]); // verified, on the loading bay
        $arushaReady = $make('arusha', [$line($w500, 70)], 'approve', ['warehouse_id' => $aru->id]);
        $kariakooLoaded = $make('kariakoo', [$line($w1500, 50)]);
        $serenaTransit = $make('serena', [$line($w500, 40), $line($w19, 12)]);
        $old = [
            'shoppers' => [$make('shoppers', [$line($w500, 60), $line($w1500, 30)]), 150],
            'arusha' => [$make('arusha', [$line($w500, 80)], 'approve', ['warehouse_id' => $aru->id]), 100],
            'kariakoo' => [$make('kariakoo', [$line($w500, 70)]), 70],
            'serena' => [$make('serena', [$line($w500, 35), $line($w19, 8)]), 45],
            'dodoma' => [$make('dodoma', [$line($w1500, 45)]), 5],
        ];
        $paidUp = $make('arusha', [$line($w1500, 40)]);
        $short = $make('kariakoo', [$line($w500, 50)]);
        $mamaDone = $make('mama', [$line($w500, 20)]);

        /* ── prepayment: invoice, receipt, verification ────────────────── */
        $prepaid = function (SalesOrder $order, bool $verify) use ($p, $bank) {
            $invoice = $this->invoices->post($this->invoices->fromOrder($order, $p['accountant']), $p['accountant']);
            $receipt = $this->receipts->record(
                ['customer_id' => $order->customer_id, 'account_id' => $bank->id, 'method' => 'bank_transfer', 'reference' => 'NMB-'.random_int(100000, 999999)],
                [['sales_invoice_id' => $invoice->id, 'amount' => (float) $invoice->total]],
                $p['cashier'],
            );
            if ($verify) {
                $this->receipts->verify($receipt, $p['finance']);
            }
        };

        $prepaid($mamaPending, false);
        $this->invoices->post($this->invoices->fromOrder($mwanzaUnpaid, $p['accountant']), $p['accountant']);
        $prepaid($mwanzaLoading, true);
        $prepaid($mamaDone, true);

        /* ── dispatch ──────────────────────────────────────────────────── */
        $vehicles = [['T 412 DKL', 'Juma Mussa'], ['T 908 DFG', 'Ramadhani Kombo'], ['T 233 EAB', 'Elia Mwakyusa'], ['T 671 DHH', 'Said Abdallah']];
        $truck = 0;
        $open = function (SalesOrder $order, Warehouse $from) use ($p, $vehicles, &$truck): ?LoadingOrder {
            [$plate, $driver] = $vehicles[$truck++ % count($vehicles)];
            $order = $order->fresh();
            $needed = $order->lines->groupBy('product_id')->map(fn ($l) => $l->sum(fn ($x) => (float) $x->quantity_approved));
            $available = $this->dispatch->availability($needed->keys()->all());
            foreach ($needed as $product => $quantity) {
                if (($available[$product][$from->id]['available'] ?? 0) < $quantity) {
                    return null; // not enough finished goods in this demo database: leave it ready
                }
            }

            return $this->dispatch->create($order, ['warehouse_id' => $from->id, 'vehicle_number' => $plate, 'driver_name' => $driver], [], $p['dispatch']);
        };
        $load = function (LoadingOrder $lo, array $less = []) use ($p) {
            $this->dispatch->setLoaded($lo, $lo->lines->mapWithKeys(fn ($l) => [$l->id => (float) $l->quantity_approved - ($less[$l->product_id] ?? 0)])->all(), $p['store']);

            return $this->dispatch->confirmLoading($lo, $p['store']);
        };
        $out = function (LoadingOrder $lo) use ($p) {
            $lo = $this->dispatch->confirmDriver($lo, null, $p['dispatch']);
            $lo = $this->dispatch->confirmSecurity($lo, 'Omari Selemani (gate)', $p['manager']);
            $lo = $this->dispatch->issueDeliveryNote($lo, $p['dispatch']);

            return $this->dispatch->issueGatePass($lo, $p['manager']);
        };
        $deliver = function (LoadingOrder $lo, string $receiver, array $short = [], ?string $remark = null) use ($p) {
            return $this->dispatch->recordDelivery($lo, ['received_by_name' => $receiver, 'received_date' => now()->toDateString(), 'remark' => $remark],
                $lo->lines->mapWithKeys(fn ($l) => [$l->id => (float) $l->quantity_loaded - ($short[$l->product_id] ?? 0)])->all(), $p['dispatch']);
        };

        // Verified and on the loading bay: quantities entered, not yet confirmed.
        if ($lo = $open($mwanzaLoading, $fg)) {
            $this->dispatch->setLoaded($lo, $lo->lines->mapWithKeys(fn ($l) => [$l->id => (float) $l->quantity_approved])->all(), $p['store']);
        }
        if ($lo = $open($kariakooLoaded, $fg)) {
            $this->dispatch->confirmDriver($load($lo), null, $p['dispatch']);
        }
        if ($lo = $open($serenaTransit, $fg)) {
            $out($load($lo));
        }

        $receivers = ['shoppers' => 'Agnes Kimaro (stores)', 'arusha' => 'Godfrey Laizer', 'kariakoo' => 'Abdul Karim', 'serena' => 'Chef Daniel Massawe', 'dodoma' => 'Zawadi Chande'];
        $deliveries = [];
        foreach ($old as $key => [$order, $days]) {
            if ($lo = $open($order, $key === 'arusha' ? $aru : $fg)) {
                $deliveries[$key] = $deliver($out($load($lo)), $receivers[$key]);
            }
        }
        if ($lo = $open($paidUp, $aru)) {
            $deliveries['paid_up'] = $deliver($out($load($lo)), 'Godfrey Laizer');
        }
        if ($lo = $open($mamaDone, $fg)) {
            $deliver($out($load($lo)), 'Mama Rukia');
        }
        if ($lo = $open($short, $fg)) {
            $deliver($out($load($lo)), 'Abdul Karim', [$w500 => 3], 'Three cartons crushed in transit near Ubungo; customer refused them.');
        }

        /* ── invoices for what was delivered, dated so every age bucket fills ── */
        foreach ($old as $key => [$order, $days]) {
            if (! isset($deliveries[$key])) {
                continue;
            }
            $date = now()->subDays($days)->toDateString();
            $invoice = $this->invoices->post($this->invoices->fromOrder($order->fresh(), $p['accountant'], $deliveries[$key], $date), $p['accountant']);
            $this->backdate($order, $deliveries[$key], $days);

            // Part payments: aged balances are what remains.
            $part = match ($key) {
                'kariakoo' => 300000, 'dodoma' => 150000, 'shoppers' => 200000, default => 0,
            };
            if ($part > 0) {
                $receipt = $this->receipts->record(
                    ['customer_id' => $order->customer_id, 'account_id' => $key === 'dodoma' ? $cash->id : $bank->id, 'receipt_date' => now()->subDays(max(1, $days - 10))->toDateString(),
                        'method' => $key === 'dodoma' ? 'mobile_money' : 'bank_transfer', 'reference' => $key === 'dodoma' ? 'MPESA-QX'.random_int(10000, 99999) : 'CRDB-'.random_int(100000, 999999)],
                    [['sales_invoice_id' => $invoice->id, 'amount' => $part]],
                    $p['cashier'],
                );
                $this->receipts->verify($receipt, $p['finance']);
            }
        }

        if (isset($deliveries['paid_up'])) {
            $invoice = $this->invoices->post($this->invoices->fromOrder($paidUp->fresh(), $p['accountant'], $deliveries['paid_up'], now()->subDays(12)->toDateString()), $p['accountant']);
            $receipt = $this->receipts->record(
                ['customer_id' => $paidUp->customer_id, 'account_id' => $bank->id, 'method' => 'bank_transfer', 'reference' => 'NBC-'.random_int(100000, 999999)],
                [['sales_invoice_id' => $invoice->id, 'amount' => (float) $invoice->total]],
                $p['cashier'],
            );
            $this->receipts->verify($receipt, $p['finance']);

            // Two cartons came back leaking: a posted return, and a draft credit for a price dispute.
            $first = $invoice->lines()->first();
            $this->credits->post($this->credits->create([
                'sales_invoice_id' => $invoice->id, 'reason' => 'Two cartons returned leaking', 'return_to_stock' => true,
                'warehouse_id' => $deliveries['paid_up']->warehouse_id,
            ], [['sales_invoice_line_id' => $first->id, 'quantity' => 2, 'batch_number' => $this->batchOf($deliveries['paid_up'], $first->product_id), 'expiry_date' => now()->addMonths(10)->toDateString()]], $p['finance']), $p['finance']);
            $this->credits->create(['sales_invoice_id' => $invoice->id, 'reason' => 'Price difference agreed with the customer'],
                [['sales_invoice_line_id' => $first->id, 'quantity' => 1]], $p['finance']);
        }

        // One credit order still waiting for a truck from Arusha, and approved orders dated across the last weeks.
        $this->backdate($arushaReady, null, 2);
    }

    /** Moves the sales-side dates of a delivered order back, so the demo reads like real history. */
    private function backdate(SalesOrder $order, ?LoadingOrder $loading, int $days): void
    {
        $when = now()->subDays($days + 3);
        $order->forceFill(['order_date' => $when->toDateString(), 'submitted_at' => $when, 'approved_at' => $when->copy()->addHours(5), 'created_at' => $when])->save();

        if ($loading) {
            $day = now()->subDays($days + 1);
            $loading->forceFill([
                'planned_date' => $day->toDateString(), 'loaded_at' => $day->copy()->setTime(9, 30), 'driver_confirmed_at' => $day->copy()->setTime(9, 50),
                'security_confirmed_at' => $day->copy()->setTime(10, 5), 'delivery_note_issued_at' => $day->copy()->setTime(10, 0),
                'gate_pass_issued_at' => $day->copy()->setTime(10, 10), 'received_date' => now()->subDays($days)->toDateString(),
                'pod_recorded_at' => now()->subDays($days)->setTime(15, 20), 'created_at' => $day->copy()->setTime(8, 0),
            ])->save();
        }
    }

    private function batchOf(LoadingOrder $loading, int $productId): ?string
    {
        return DB::table('stock_movements')->where('stock_document_id', $loading->stock_document_id)->where('product_id', $productId)->value('batch_number') ?: null;
    }
}
