<?php

namespace Database\Seeders\Erp;

use App\Models\Erp\Account;
use App\Models\Erp\Procurement\ProcurementSetting;
use App\Models\Erp\Procurement\PurchaseOrder;
use App\Models\Erp\Procurement\PurchaseRequisition;
use App\Models\Erp\Product;
use App\Models\Erp\Supplier;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Services\Erp\Procurement\PurchaseOrders;
use App\Services\Erp\Procurement\Requisitions;
use App\Services\Erp\Procurement\Rfqs;
use App\Services\Erp\Procurement\SupplierInvoices;
use App\Services\Erp\Procurement\SupplierPayments;
use App\Support\TenantContext;
use Illuminate\Database\Seeder;

/**
 * Watercom's purchasing: requisitions in every status, a request for
 * quotation with three quotations waiting to be compared and another already
 * awarded, purchase orders from draft to closed (one half received), supplier
 * invoices matched against them (one with a price variance waiting for the
 * CEO), and payments, so the payables ageing has something in every bucket.
 *
 * Everything goes through the real services, so stock, GRNI, payables and the
 * bank move exactly as they would for a person. Re-runnable: the history is
 * written only into a company that has no requisitions yet.
 */
class Step30ProcurementSeeder extends Seeder
{
    public function __construct(
        private readonly TenantContext $tenant,
        private readonly Requisitions $requisitions,
        private readonly Rfqs $rfqs,
        private readonly PurchaseOrders $orders,
        private readonly SupplierInvoices $invoices,
        private readonly SupplierPayments $payments,
    ) {}

    public function run(): void
    {
        $company = $this->tenant->company();

        if (! $company) {
            return;
        }

        $modules = is_array($company->modules) ? $company->modules : [];
        if (! in_array('procurement', $modules, true)) {
            $company->forceFill(['modules' => [...$modules, 'procurement']])->save();
        }

        ProcurementSetting::current()->update([
            'approval_threshold' => 5000000, 'price_tolerance_percent' => 2,
            'receipt_tolerance_percent' => 0, 'quantity_tolerance_percent' => 0, 'default_vat_rate' => 18,
        ]);

        $suppliers = $this->suppliers($company->id);

        if (PurchaseRequisition::query()->exists()) {
            return;
        }

        $people = [];
        foreach (['upendo', 'joseph', 'emmanuel', 'grace', 'mwajuma', 'neema'] as $name) {
            $person = User::query()->where('email', "{$name}@watercom.test")->first();
            if (! $person) {
                return;
            }
            $people[$name] = $person;
        }

        $product = fn (string $sku) => Product::query()->where('sku', $sku)->firstOrFail();
        $items = [
            'preform' => $product('RM-PRF-28'), 'cap' => $product('RM-CAP-28'),
            'label' => $product('PK-LBL-500'), 'shrink' => $product('PK-SHR-24'),
        ];
        $store = Warehouse::query()->where('code', 'MAIN')->firstOrFail();
        $bank = Account::query()->where('system_key', 'bank')->value('id');
        $repairs = Account::query()->where('system_key', 'vehicle_maintenance')->value('id');

        $this->requisitionHistory($people, $items);
        $this->quotations($people, $items, $suppliers);
        $this->orderHistory($people, $items, $suppliers, $store, $bank, $repairs);
    }

    /** @return array<string, Supplier> */
    private function suppliers(int $companyId): array
    {
        $extra = [
            'kariakoo' => ['SUP-0101', 'Kariakoo Packaging Traders', 'Packaging', 'Halima Said', '+255 715 330 812', 30, 'NMB Bank', '2045 9912 300', 'Dar es Salaam'],
            'mwanza' => ['SUP-0102', 'Lake Zone Industrial Supplies', 'Packaging', 'Daudi Magesa', '+255 768 221 904', 21, 'CRDB Bank', '0152 8890 2210', 'Mwanza'],
        ];

        foreach ($extra as $key => [$code, $name, $category, $contact, $phone, $terms, $bank, $account, $city]) {
            Supplier::query()->firstOrCreate(['name' => $name], [
                'company_id' => $companyId, 'code' => Supplier::query()->where('code', $code)->exists() ? $code.'P' : $code,
                'category' => $category, 'contact_person' => $contact, 'phone' => $phone, 'city' => $city,
                'payment_terms_days' => $terms, 'bank_name' => $bank, 'bank_account_name' => $name, 'bank_account_number' => $account,
            ]);
        }

        $find = fn (string $code, string $name) => Supplier::query()->where('code', $code)->first() ?? Supplier::query()->where('name', $name)->firstOrFail();

        return [
            'pet' => $find('SUP-0001', 'East Africa PET Industries'),
            'pack' => $find('SUP-0002', 'Dar Packaging Solutions'),
            'tyres' => $find('SUP-0003', 'Mlimani Tyre Centre'),
            'kariakoo' => Supplier::query()->where('name', 'Kariakoo Packaging Traders')->firstOrFail(),
            'mwanza' => Supplier::query()->where('name', 'Lake Zone Industrial Supplies')->firstOrFail(),
        ];
    }

    private function requisitionHistory(array $people, array $items): void
    {
        $line = fn (Product $p, float $qty, float $price) => ['line_type' => 'stock', 'product_id' => $p->id, 'quantity' => $qty, 'estimated_unit_price' => $price];
        $raise = fn (string $who, string $why, array $lines, int $days = 10) => $this->requisitions->create([
            'justification' => $why, 'needed_by' => now()->addDays($days)->toDateString(), 'lines' => $lines,
        ], $people[$who]);

        // Draft: still being written.
        $raise('upendo', 'Labels for the new 1.5 litre line launch in Arusha', [$line($items['label'], 30000, 12)], 21);

        // Submitted, waiting for the head of procurement.
        $waiting = $raise('upendo', 'Caps for next week\'s production run at Mbezi', [$line($items['cap'], 20000, 18)], 7);
        $this->requisitions->submit($waiting, $people['upendo']);

        // Above the threshold: the HOD has approved, the CEO's approval is still needed.
        $large = $raise('upendo', 'Preforms for the December peak, three weeks of production', [$line($items['preform'], 60000, 95)], 14);
        $this->requisitions->submit($large, $people['upendo']);
        $this->requisitions->approve($large, $people['joseph'], 'Within the quarterly plan.');

        // Rejected, with the reason kept.
        $rejected = $raise('upendo', 'Spare shrink film stock for the Mwanza depot', [$line($items['shrink'], 150, 5400)]);
        $this->requisitions->submit($rejected, $people['upendo']);
        $this->requisitions->reject($rejected, $people['joseph'], 'Mwanza depot still holds six weeks of film; raise again in January.');

        // Cancelled by the person who raised it.
        $cancelled = $raise('joseph', 'Pallet wrap trial from a new supplier', [
            ['line_type' => 'service', 'description' => 'Pallet wrapping machine trial, two days on site', 'quantity' => 1, 'estimated_unit_price' => 450000],
        ]);
        $this->requisitions->cancel($cancelled, $people['joseph']);
    }

    private function quotations(array $people, array $items, array $suppliers): void
    {
        // Approved, sent to three suppliers, all three have quoted: ready for comparison and award.
        $requisition = $this->requisitions->create([
            'justification' => 'Shrink film for the 24-pack line, January requirement',
            'needed_by' => now()->addDays(18)->toDateString(),
            'lines' => [['line_type' => 'stock', 'product_id' => $items['shrink']->id, 'quantity' => 400, 'estimated_unit_price' => 5200]],
        ], $people['upendo']);
        $this->requisitions->submit($requisition, $people['upendo']);
        $this->requisitions->approve($requisition, $people['joseph'], 'Approved, get three quotations.');

        $rfq = $this->rfqs->create([
            'purchase_requisition_id' => $requisition->id, 'title' => 'Shrink film 24-pack, 400 kg',
            'issue_date' => now()->subDays(6)->toDateString(), 'closing_date' => now()->addDays(2)->toDateString(),
            'supplier_ids' => [$suppliers['pack']->id, $suppliers['kariakoo']->id, $suppliers['mwanza']->id],
        ], $people['upendo']);
        $this->rfqs->send($rfq, $people['upendo']);

        $lineId = $rfq->lines->first()->id;
        foreach ([
            ['pack', 5250, 7, 'DPS-Q-2291', '30 days', 'Delivered to Mbezi'],
            ['kariakoo', 5050, 12, 'KPT-118', '14 days', 'Ex-warehouse Kariakoo'],
            ['mwanza', 5150, 21, 'LZ-Q-77', '21 days', 'Delivered, freight included'],
        ] as [$key, $price, $lead, $ref, $terms, $delivery]) {
            $this->rfqs->quote($rfq, [
                'supplier_id' => $suppliers[$key]->id, 'reference' => $ref, 'quotation_date' => now()->subDays(3)->toDateString(),
                'valid_until' => now()->addDays(27)->toDateString(), 'lead_time_days' => $lead,
                'payment_terms' => $terms, 'delivery_terms' => $delivery,
                'lines' => [['purchase_rfq_line_id' => $lineId, 'unit_price' => $price, 'vat_rate' => 18]],
            ], $people['upendo']);
        }
    }

    private function orderHistory(array $people, array $items, array $suppliers, Warehouse $store, ?int $bank, ?int $repairs): void
    {
        $upendo = $people['upendo'];
        $stock = fn (Product $p, float $qty, float $price) => ['line_type' => 'stock', 'product_id' => $p->id, 'quantity' => $qty, 'unit_price' => $price, 'vat_rate' => 18];
        $order = fn (Supplier $s, array $lines, int $daysAgo, array $extra = []) => $this->orders->create([
            'supplier_id' => $s->id, 'warehouse_id' => $store->id, 'lines' => $lines,
            'order_date' => now()->subDays($daysAgo)->toDateString(), 'expected_date' => now()->subDays($daysAgo - 7)->toDateString(), ...$extra,
        ], $upendo);
        $approve = function (PurchaseOrder $po, bool $send = true) use ($people, $upendo) {
            $po = $this->orders->submit($po, $upendo);
            $po = $this->orders->approve($po, $people['joseph'], 'Prices as agreed.');
            if ($po->status !== PurchaseOrder::STATUS_APPROVED) {
                $po = $this->orders->approve($po, $people['emmanuel'], 'Approved above threshold.');
            }

            return $send ? $this->orders->send($po, $upendo) : $po;
        };
        $receive = fn (PurchaseOrder $po, float $qty, int $daysAgo, string $note) => $this->orders->receive($po, [
            'warehouse_id' => $store->id, 'received_date' => now()->subDays($daysAgo)->toDateString(), 'delivery_note' => $note,
            'lines' => [['purchase_order_line_id' => $po->lines()->value('id'), 'quantity' => $qty, 'batch_number' => 'B'.now()->subDays($daysAgo)->format('ymd')]],
        ], $people['neema']);
        $invoice = fn (PurchaseOrder $po, string $number, float $qty, float $price, int $daysAgo, int $dueDaysAgo) => $this->invoices->create([
            'purchase_order_id' => $po->id, 'supplier_invoice_number' => $number,
            'invoice_date' => now()->subDays($daysAgo)->toDateString(), 'due_date' => now()->subDays($dueDaysAgo)->toDateString(),
            'lines' => [['purchase_order_line_id' => $po->lines()->value('id'), 'quantity' => $qty, 'unit_price' => $price]],
        ], $people['grace']);
        $pay = fn ($inv, float $amount, int $daysAgo, string $ref) => $bank ? $this->payments->post($this->payments->create([
            'supplier_id' => $inv->supplier_id, 'account_id' => $bank, 'amount' => $amount, 'method' => 'bank_transfer',
            'reference' => $ref, 'payment_date' => now()->subDays($daysAgo)->toDateString(),
            'allocations' => [['supplier_invoice_id' => $inv->id, 'amount' => $amount]],
        ], $people['mwajuma']), $people['mwajuma']) : null;

        // Over 90 days: preforms received in August, half paid.
        $old = $approve($order($suppliers['pet'], [$stock($items['preform'], 30000, 95)], 135));
        $receive($old, 30000, 132, 'DN-EAPI-6610');
        $oldInvoice = $this->invoices->post($invoice($old, 'EAPI-INV-4402', 30000, 95, 130, 100), $people['grace']);
        $pay($oldInvoice, 1500000, 95, 'CRDB-TT-55102');

        // 61 to 90 days: shrink film from Kariakoo, unpaid.
        $film = $approve($order($suppliers['kariakoo'], [$stock($items['shrink'], 300, 5100)], 104));
        $receive($film, 300, 101, 'KPT-DN-0931');
        $this->invoices->post($invoice($film, 'KPT-INV-2210', 300, 5100, 100, 70), $people['grace']);

        // 31 to 60 days, closed: caps received and invoiced in full, part paid.
        $caps = $approve($order($suppliers['pet'], [$stock($items['cap'], 50000, 18)], 70));
        $receive($caps, 50000, 67, 'DN-EAPI-7702');
        $capsInvoice = $this->invoices->post($invoice($caps, 'EAPI-INV-4519', 50000, 18, 65, 35), $people['grace']);
        $pay($capsInvoice, 500000, 30, 'CRDB-TT-58810');

        // 1 to 30 days, a service: truck tyres replaced, confirmed, invoiced and half paid.
        $tyres = $approve($this->orders->create([
            'supplier_id' => $suppliers['tyres']->id, 'order_date' => now()->subDays(26)->toDateString(),
            'notes' => 'Truck T 482 DLM, Dar es Salaam to Arusha route',
            'lines' => [
                ['line_type' => 'service', 'description' => 'Six drive tyres 315/80 R22.5 fitted, truck T 482 DLM', 'quantity' => 6, 'unit_price' => 780000, 'vat_rate' => 18, 'expense_account_id' => $repairs],
                ['line_type' => 'service', 'description' => 'Wheel alignment and balancing', 'quantity' => 1, 'unit_price' => 120000, 'vat_rate' => 18, 'expense_account_id' => $repairs],
            ],
        ], $upendo));
        $tyreLines = $tyres->lines()->orderBy('id')->get();
        $this->orders->confirmService($tyres, [
            'received_date' => now()->subDays(24)->toDateString(), 'delivery_note' => 'MTC-JC-3381',
            'lines' => $tyreLines->map(fn ($l) => ['purchase_order_line_id' => $l->id, 'quantity' => (float) $l->quantity])->all(),
        ], $people['neema']);
        $tyreInvoice = $this->invoices->post($this->invoices->create([
            'purchase_order_id' => $tyres->id, 'supplier_invoice_number' => 'MTC-0457',
            'invoice_date' => now()->subDays(23)->toDateString(), 'due_date' => now()->subDays(16)->toDateString(),
            'lines' => $tyreLines->map(fn ($l) => ['purchase_order_line_id' => $l->id, 'quantity' => (float) $l->quantity, 'unit_price' => (float) $l->unit_price])->all(),
        ], $people['grace']), $people['grace']);
        $pay($tyreInvoice, round((float) $tyreInvoice->total / 2, 2), 14, 'NBC-EFT-20981');

        // Current, not yet due: Lake Zone shrink film for the Mwanza depot.
        $lake = $approve($order($suppliers['mwanza'], [$stock($items['shrink'], 120, 5150)], 12));
        $receive($lake, 120, 8, 'LZ-DN-3302');
        $this->invoices->post($invoice($lake, 'LZ-INV-0912', 120, 5150, 6, -15), $people['grace']);

        // Received in full; the supplier billed labels at 12.60 against 12 ordered: waiting for the CEO.
        $labels = $approve($order($suppliers['pack'], [$stock($items['label'], 80000, 12)], 9));
        $receive($labels, 80000, 5, 'DPS-DN-1187');
        $invoice($labels, 'DPS-INV-0518', 80000, 12.6, 3, -11);

        // From an awarded quotation, above the threshold: half the preforms are in, and the part received is invoiced, waiting to post.
        $preformReq = $this->requisitions->create([
            'justification' => 'Preforms for the new 1.5 litre line', 'needed_by' => now()->addDays(5)->toDateString(),
            'lines' => [['line_type' => 'stock', 'product_id' => $items['preform']->id, 'quantity' => 60000, 'estimated_unit_price' => 96]],
        ], $upendo);
        $this->requisitions->submit($preformReq, $upendo);
        $this->requisitions->approve($preformReq, $people['joseph'], 'Needed for the line launch.');
        $this->requisitions->approve($preformReq, $people['emmanuel'], 'Approved.');
        $rfq = $this->rfqs->create([
            'purchase_requisition_id' => $preformReq->id, 'title' => 'PET preforms 28g, 60,000 pcs',
            'issue_date' => now()->subDays(20)->toDateString(), 'closing_date' => now()->subDays(15)->toDateString(),
            'supplier_ids' => [$suppliers['pet']->id, $suppliers['kariakoo']->id],
        ], $upendo);
        $this->rfqs->send($rfq, $upendo);
        $rfqLine = $rfq->lines->first()->id;
        $winner = $this->rfqs->quote($rfq, ['supplier_id' => $suppliers['pet']->id, 'reference' => 'EAPI-Q-881', 'lead_time_days' => 5, 'payment_terms' => '30 days',
            'lines' => [['purchase_rfq_line_id' => $rfqLine, 'unit_price' => 94, 'vat_rate' => 18]]], $upendo);
        $this->rfqs->quote($rfq, ['supplier_id' => $suppliers['kariakoo']->id, 'reference' => 'KPT-151', 'lead_time_days' => 14, 'payment_terms' => '14 days',
            'lines' => [['purchase_rfq_line_id' => $rfqLine, 'unit_price' => 97, 'vat_rate' => 18]]], $upendo);
        $this->rfqs->award($rfq, $winner->id, 'Lowest price and the shortest lead time; delivers to Mbezi.', $upendo);
        $partial = $approve($this->orders->create([
            'supplier_quotation_id' => $winner->id, 'warehouse_id' => $store->id,
            'order_date' => now()->subDays(14)->toDateString(), 'expected_date' => now()->addDays(3)->toDateString(),
        ], $upendo));
        $receive($partial, 35000, 4, 'DN-EAPI-8120');
        $invoice($partial, 'EAPI-INV-4630', 35000, 94, 2, -28);

        // Sent, nothing received yet.
        $approve($order($suppliers['pet'], [$stock($items['cap'], 40000, 18)], 3));

        // Approved, not yet sent.
        $approve($order($suppliers['pack'], [$stock($items['shrink'], 200, 5200)], 2), false);

        // Submitted, waiting for approval.
        $this->orders->submit($order($suppliers['kariakoo'], [$stock($items['label'], 50000, 12)], 1), $upendo);

        // Draft.
        $order($suppliers['pack'], [$stock($items['label'], 25000, 12.2)], 0, ['notes' => 'Confirm the new artwork before sending.']);

        // Cancelled.
        $this->orders->cancel($order($suppliers['mwanza'], [$stock($items['cap'], 10000, 19)], 30), 'Supplier could not deliver before the Christmas shutdown.', $upendo);
    }
}
