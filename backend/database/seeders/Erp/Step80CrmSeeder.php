<?php

namespace Database\Seeders\Erp;

use App\Models\Company;
use App\Models\Erp\Crm\Activity;
use App\Models\Erp\Crm\Lead;
use App\Models\Erp\Crm\Opportunity;
use App\Models\Erp\Customer;
use App\Models\Erp\Documents\Document;
use App\Models\Erp\Documents\DocumentLink;
use App\Models\Erp\Documents\Folder;
use App\Models\User;
use App\Services\Erp\Crm\Pipeline;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\Documents\DocumentStore;
use App\Support\TenantContext;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Watercom's CRM and document store: thirty leads across the regions, fifteen
 * deals in every stage, follow-ups due today and overdue, a few converted
 * customers, and a folder tree holding small generated files on the private
 * disk, among them a TBS certificate and a vehicle insurance about to expire.
 *
 * Re-runnable: people are matched by email, and each half is seeded only into
 * a company that has none of it yet.
 */
class Step80CrmSeeder extends Seeder
{
    public function __construct(
        private readonly TenantContext $tenant,
        private readonly Pipeline $pipeline,
        private readonly DocumentNumberer $numbers,
        private readonly DocumentStore $store,
    ) {}

    public function run(): void
    {
        $company = $this->tenant->company();

        if (! $company) {
            return;
        }

        $modules = $company->modules ?? [];
        if (array_diff(['crm', 'documents'], $modules)) {
            $company->forceFill(['modules' => array_values(array_unique([...$modules, 'crm', 'documents']))])->save();
        }

        $people = $this->people($company);

        if (! Lead::query()->exists()) {
            $this->crm($people);
        }

        if (! Folder::query()->exists()) {
            $this->documents($company, $people);
        }
    }

    /** @return array<string, User> */
    private function people(Company $company): array
    {
        $rows = [
            'zawadi' => ['Zawadi Mrema', 'zawadi@watercom.test', User::ROLE_SALES, 'Sales Executive, Northern zone', 'WC-0180'],
            'baraka' => ['Baraka Mwakyusa', 'baraka@watercom.test', User::ROLE_SALES, 'Sales Executive, Lake zone', 'WC-0181'],
            'salma' => ['Salma Kassim', 'salma@watercom.test', User::ROLE_MANAGER, 'Sales Manager', 'WC-0182'],
        ];

        $people = [];
        foreach ($rows as $key => [$name, $email, $role, $title, $code]) {
            $people[$key] = User::query()->where('email', $email)->first() ?? User::create([
                'company_id' => $company->id, 'name' => $name, 'email' => $email, 'password' => 'Password123!',
                'role' => $role, 'job_title' => $title, 'employee_code' => $code,
                'status' => 'active', 'locale' => 'en', 'email_verified_at' => now(),
            ]);
        }

        $find = fn (string $email) => User::query()->where('email', $email)->first();
        $people['hassan'] = $find('hassan@watercom.test') ?? $people['zawadi'];
        $people['admin'] = $find('admin@watercom.test') ?? $people['salma'];
        $people['ceo'] = $find('emmanuel@watercom.test') ?? $people['admin'];

        return $people;
    }

    private function crm(array $people): void
    {
        $actor = $people['admin'];
        auth()->setUser($actor);

        $sellers = ['dar' => $people['hassan'], 'north' => $people['zawadi'], 'lake' => $people['baraka']];
        $owner = fn (string $region) => match ($region) {
            'Arusha', 'Kilimanjaro', 'Tanga', 'Manyara' => $sellers['north'],
            'Mwanza', 'Kagera', 'Shinyanga', 'Mara' => $sellers['lake'],
            default => $sellers['dar'],
        };

        // [contact, company, phone, region, source, status, estimated value, days ago]
        $leads = [
            ['Rehema Mollel', 'Mollel General Supplies', '+255 754 210 334', 'Arusha', 'referral', 'qualified', 6500000, 21],
            ['Juma Said', 'Said & Sons Wholesale', '+255 713 442 118', 'Dar es Salaam', 'walk_in', 'qualified', 9800000, 30],
            ['Anna Kileo', 'Kileo Mini Market', '+255 765 330 901', 'Kilimanjaro', 'field_visit', 'qualified', 3200000, 18],
            ['Daudi Magesa', 'Lake Victoria Lodges', '+255 782 115 640', 'Mwanza', 'website', 'qualified', 14500000, 26],
            ['Fatuma Ally', 'Ally Kiosks Kariakoo', '+255 715 908 221', 'Dar es Salaam', 'phone', 'new', 1800000, 1],
            ['Peter Massawe', 'Moshi Coffee House', '+255 754 662 019', 'Kilimanjaro', 'social_media', 'new', 2400000, 2],
            ['Neema Laizer', 'Laizer Safari Camps', '+255 768 223 145', 'Arusha', 'trade_show', 'contacted', 11000000, 9],
            ['Hamisi Mrisho', 'Mrisho Distributors', '+255 787 431 556', 'Morogoro', 'referral', 'contacted', 7600000, 12],
            ['Grace Nyirenda', 'Mbeya Highland Hotel', '+255 756 870 312', 'Mbeya', 'website', 'qualified', 8900000, 15],
            ['Yusuf Omari', 'Omari Fresh Mart', '+255 777 102 993', 'Zanzibar', 'phone', 'new', 2100000, 3],
            ['Esther Wambura', 'Wambura Supermarket', '+255 752 640 718', 'Mara', 'field_visit', 'contacted', 5400000, 8],
            ['Khamis Abdallah', 'Stone Town Beach Resort', '+255 773 555 120', 'Zanzibar', 'trade_show', 'qualified', 16500000, 20],
            ['Lucy Mushi', 'Mushi Catering Services', '+255 762 091 447', 'Dar es Salaam', 'referral', 'new', 1500000, 0],
            ['Joseph Kimaro', 'Kimaro Petrol & Shop', '+255 714 338 602', 'Dodoma', 'field_visit', 'contacted', 3900000, 6],
            ['Mariam Hassan', 'Dodoma University Canteen', '+255 755 284 019', 'Dodoma', 'website', 'qualified', 7200000, 11],
            ['Elia Mwita', 'Mwita Hardware & Grocery', '+255 784 772 930', 'Mwanza', 'walk_in', 'lost', 2600000, 40],
            ['Sophia Temba', 'Temba Events', '+255 716 450 287', 'Arusha', 'social_media', 'contacted', 4300000, 5],
            ['Abdul Rashid', 'Tanga Port Canteen', '+255 769 813 405', 'Tanga', 'phone', 'new', 2800000, 4],
            ['Halima Juma', 'Halima Food Vendors Group', '+255 786 129 764', 'Dar es Salaam', 'referral', 'contacted', 3100000, 7],
            ['Godfrey Lyimo', 'Lyimo Wholesalers Moshi', '+255 753 601 228', 'Kilimanjaro', 'trade_show', 'lost', 6800000, 45],
            ['Rose Mhando', 'Morogoro Teachers College', '+255 718 245 371', 'Morogoro', 'website', 'new', 4100000, 2],
            ['Selemani Bakari', 'Bakari Minimarts', '+255 775 384 016', 'Dar es Salaam', 'walk_in', 'qualified', 5600000, 14],
            ['Agnes Shayo', 'Bukoba Lakeside Inn', '+255 764 903 552', 'Kagera', 'phone', 'contacted', 3700000, 10],
            ['Ibrahimu Nassoro', 'Nassoro Transport Kiosks', '+255 789 210 667', 'Shinyanga', 'field_visit', 'new', 1900000, 1],
            ['Catherine Mrema', 'Kilimanjaro Hiking Outfitters', '+255 757 538 194', 'Kilimanjaro', 'social_media', 'qualified', 6200000, 13],
            ['Musa Kombo', 'Kombo Water Point', '+255 712 774 830', 'Pwani', 'referral', 'lost', 1200000, 35],
            ['Winfrida Mallya', 'Mallya Supermarket Sinza', '+255 766 019 245', 'Dar es Salaam', 'website', 'new', 4800000, 0],
            ['Shabani Mfinanga', 'Babati Agro Dealers', '+255 783 662 571', 'Manyara', 'field_visit', 'contacted', 2200000, 6],
            ['Doris Kapinga', 'Iringa Highlands School', '+255 754 117 908', 'Iringa', 'referral', 'new', 3500000, 3],
            ['Hussein Mtoro', 'Mtoro Gym & Spa', '+255 715 863 402', 'Dar es Salaam', 'social_media', 'contacted', 1700000, 8],
        ];

        $created = [];
        foreach ($leads as [$contact, $business, $phone, $region, $source, $status, $value, $ago]) {
            $lead = Lead::create([
                'number' => $this->numbers->next('LEAD'),
                'contact_name' => $contact, 'company_name' => $business, 'phone' => $phone,
                'email' => strtolower(str_replace(' ', '.', $contact)).'@example.co.tz',
                'region' => $region, 'source' => $source, 'status' => $status, 'estimated_value' => $value,
                'lost_reason' => $status === 'lost' ? 'Chose a cheaper local bottler' : null,
                'owner_id' => $owner($region)->id, 'created_by' => $owner($region)->id,
                'created_at' => now()->subDays($ago), 'updated_at' => now()->subDays(max(0, $ago - 2)),
            ]);
            $created[$contact] = $lead;
        }

        // Four qualified leads became customers, each with a deal.
        $converted = [];
        foreach (['Rehema Mollel' => 'proposal', 'Juma Said' => 'negotiation', 'Daudi Magesa' => 'negotiation', 'Anna Kileo' => 'prospecting'] as $contact => $stage) {
            $result = $this->pipeline->convert($created[$contact], [
                'title' => $created[$contact]->company_name.': monthly water supply', 'stage' => $stage,
                'expected_close_date' => now()->addDays(random_int(10, 75))->toDateString(),
            ], $actor);
            $converted[] = $result['opportunity'];
        }

        $customers = Customer::query()->whereIn('code', ['CUS-0001', 'CUS-0002', 'CUS-0003', 'CUS-0004', 'CUS-0005'])->get()->keyBy('code');
        $customer = fn (string $code) => $customers[$code]->id ?? null;

        // [title, customer code, stage, value, close in days (negative = closed days ago), owner, reason]
        $deals = [
            ['Shoppers Masaki: private label 500ml', 'CUS-0001', 'proposal', 18500000, 25, 'dar', null],
            ['Kariakoo Wholesalers: Q1 volume contract', 'CUS-0002', 'negotiation', 42000000, 12, 'dar', null],
            ['Serena Hotel: 19L dispensers', 'CUS-0004', 'prospecting', 9600000, 55, 'dar', null],
            ['Arusha Distributors: northern depot stock', 'CUS-0005', 'proposal', 27500000, 40, 'north', null],
            ['Mama Ntilie network: sachet water', 'CUS-0003', 'prospecting', 4200000, 70, 'dar', null],
            ['Serena Hotel: conference season top-up', 'CUS-0004', 'won', 6800000, -6, 'dar', 'relationship'],
            ['Arusha Distributors: festive season', 'CUS-0005', 'won', 15400000, -20, 'north', 'delivery'],
            ['Kariakoo Wholesalers: 1.5L trial', 'CUS-0002', 'won', 7300000, -40, 'dar', 'price'],
            ['Shoppers Masaki: glass bottles', 'CUS-0001', 'lost', 12000000, -15, 'dar', 'price'],
            ['Mama Ntilie network: branded cups', 'CUS-0003', 'lost', 2500000, -50, 'dar', 'no_budget'],
            ['Kariakoo Wholesalers: Mwanza branch', 'CUS-0002', 'prospecting', 13200000, 95, 'lake', null],
        ];

        foreach ($deals as [$title, $code, $stage, $value, $days, $who, $reason]) {
            $closed = in_array($stage, ['won', 'lost'], true);
            $date = now()->addDays($days);
            Opportunity::create([
                'number' => $this->numbers->next('OPP'), 'title' => $title, 'customer_id' => $customer($code),
                'stage' => $stage, 'value' => $value, 'probability' => Opportunity::DEFAULT_PROBABILITY[$stage],
                'expected_close_date' => $date->toDateString(), 'owner_id' => $sellers[$who]->id,
                'close_reason' => $reason, 'closed_at' => $closed ? $date : null,
                'close_note' => $stage === 'lost' ? 'Competitor offered a lower case price' : null,
                'stage_changed_at' => $closed ? $date : now()->subDays(random_int(1, 12)),
                'created_by' => $sellers[$who]->id, 'created_at' => now()->subDays(abs($days) + 20),
            ]);
        }

        $opportunities = Opportunity::query()->orderBy('id')->get();
        $today = today();

        // [type, subject, due (days from today, hour), owner, linked lead contact or deal index, done]
        $activities = [
            ['call', 'Confirm delivery schedule with procurement', [0, 10], 'dar', ['deal', 5], false],
            ['meeting', 'Price review with Kariakoo Wholesalers', [0, 14], 'dar', ['deal', 5], false],
            ['visit', 'Site visit: Laizer Safari Camps', [0, 11], 'north', ['lead', 'Neema Laizer'], false],
            ['task', 'Send revised quotation', [0, 16], 'lake', ['deal', 3], false],
            ['call', 'Follow up on proposal', [-3, 9], 'north', ['deal', 0], false],
            ['task', 'Prepare dispenser placement plan', [-2, 15], 'dar', ['deal', 6], false],
            ['call', 'Chase signed agreement', [-5, 10], 'dar', ['deal', 1], false],
            ['visit', 'Tasting session at Mbeya Highland Hotel', [-1, 13], 'dar', ['lead', 'Grace Nyirenda'], false],
            ['call', 'Introduce Watercom range', [-4, 11], 'north', ['lead', 'Sophia Temba'], false],
            ['meeting', 'Quarterly review', [2, 10], 'dar', ['deal', 8], false],
            ['visit', 'Bukoba depot walk-through', [3, 12], 'lake', ['lead', 'Agnes Shayo'], false],
            ['task', 'Collect TIN and business licence copy', [5, 9], 'dar', ['lead', 'Selemani Bakari'], false],
            ['call', 'Thank-you call after first delivery', [-8, 10], 'dar', ['deal', 10], true],
            ['meeting', 'Contract signing', [-12, 15], 'north', ['deal', 11], true],
            ['visit', 'Sample drop-off', [-6, 11], 'lake', ['lead', 'Esther Wambura'], true],
        ];

        foreach ($activities as [$type, $subject, [$days, $hour], $who, [$kind, $ref], $done]) {
            $deal = $kind === 'deal' ? ($opportunities[$ref] ?? null) : null;
            $lead = $kind === 'lead' ? ($created[$ref] ?? null) : null;
            $due = $today->copy()->addDays($days)->setTime($hour, 0);

            Activity::create([
                'type' => $type, 'subject' => $subject, 'due_at' => $due,
                'lead_id' => $lead?->id, 'opportunity_id' => $deal?->id, 'customer_id' => $deal?->customer_id,
                'owner_id' => ($deal?->owner_id ?? $lead?->owner_id) ?? $sellers[$who]->id,
                'completed_at' => $done ? $due->copy()->addHour() : null,
                'completed_by' => $done ? $sellers[$who]->id : null,
                'outcome' => $done ? 'Done, customer happy to continue' : null,
                'created_by' => $sellers[$who]->id,
            ]);
        }

        auth()->forgetUser();
    }

    private function documents(Company $company, array $people): void
    {
        $admin = $people['admin'];
        auth()->setUser($admin);

        $folder = fn (string $name, array $extra = [], ?int $parent = null) => Folder::create([
            'name' => $name, 'parent_id' => $parent, 'created_by' => $admin->id, ...$extra,
        ]);

        $tree = [
            'company' => $folder('Company', ['description' => 'Registration, profile and statutory records', 'retention_years' => 10]),
            'contracts' => $folder('Contracts', ['description' => 'Customer and supplier agreements', 'retention_years' => 7,
                'access_scope' => 'roles', 'access_roles' => [User::ROLE_CEO, User::ROLE_DIRECTOR, User::ROLE_MANAGER, User::ROLE_FINANCE, User::ROLE_ACCOUNTANT, User::ROLE_SALES]]),
            'licences' => $folder('Licences & permits', ['description' => 'TBS, TMDA, business licence, fire and water permits']),
            'insurance' => $folder('Insurance', ['description' => 'Property, stock and liability cover', 'retention_years' => 7]),
            'hr' => $folder('HR policies', ['description' => 'Handbook and policies; HR and leadership only',
                'access_scope' => 'roles', 'access_roles' => [User::ROLE_HR_MANAGER, User::ROLE_CEO, User::ROLE_DIRECTOR]]),
            'vehicles' => $folder('Vehicles', ['description' => 'Registration, road licences and insurance per vehicle']),
        ];
        $tree['customer_contracts'] = $folder('Customers', [], $tree['contracts']->id);
        $tree['supplier_contracts'] = $folder('Suppliers', [], $tree['contracts']->id);

        $vehicle = Schema::hasTable('vehicles')
            ? DB::table('vehicles')->where('company_id', $company->id)->orderBy('id')->value('id')
            : null;
        $customer = Customer::query()->where('code', 'CUS-0002')->first();

        // [folder, title, type, file name, issued days ago, expires in days, tags, links, extra versions]
        $files = [
            ['company', 'Certificate of Incorporation', 'certificate', 'certificate-of-incorporation.pdf', 2900, null, ['brela', 'statutory'], [], 0],
            ['company', 'Company profile 2026', 'report', 'watercom-company-profile.pdf', 60, null, ['profile', 'marketing'], [], 1],
            ['company', 'TIN certificate', 'certificate', 'tin-certificate.pdf', 1500, null, ['tra', 'tax'], [], 0],
            ['licences', 'TBS Certificate of Conformity: drinking water', 'certificate', 'tbs-certificate-drinking-water.pdf', 340, 25, ['tbs', 'quality'], [], 0],
            ['licences', 'Business licence, Kinondoni Municipal', 'licence', 'business-licence-2026.pdf', 150, 215, ['municipal'], [], 0],
            ['licences', 'Fire safety certificate', 'certificate', 'fire-safety-certificate.pdf', 370, -5, ['fire', 'safety'], [], 0],
            ['licences', 'Water abstraction permit, Wami Ruvu Basin', 'permit', 'water-abstraction-permit.pdf', 400, 60, ['water', 'basin'], [], 0],
            ['insurance', 'Fire and burglary policy', 'insurance', 'fire-burglary-policy.pdf', 220, 145, ['property'], [], 0],
            ['insurance', 'Goods in transit cover', 'insurance', 'goods-in-transit.pdf', 300, 65, ['stock', 'transit'], [], 0],
            ['customer_contracts', 'Supply agreement: Kariakoo Wholesalers', 'contract', 'supply-agreement-kariakoo.pdf', 90, 275, ['supply'], $customer ? [['customer', $customer->id]] : [], 1],
            ['supplier_contracts', 'Preform supply contract', 'contract', 'preform-supply-contract.pdf', 200, 165, ['packaging'], [], 0],
            ['hr', 'Staff handbook 2026', 'policy', 'staff-handbook-2026.pdf', 45, null, ['handbook'], [], 0],
            ['hr', 'Leave policy', 'policy', 'leave-policy.txt', 120, null, ['leave'], [], 0],
            ['vehicles', 'Comprehensive insurance: T 512 DKL', 'insurance', 'insurance-t512dkl.pdf', 347, 18, ['vehicle', 'T 512 DKL'], $vehicle ? [['vehicle', $vehicle]] : [], 0],
            ['vehicles', 'Road licence: T 512 DKL', 'licence', 'road-licence-t512dkl.pdf', 275, 90, ['vehicle', 'T 512 DKL'], $vehicle ? [['vehicle', $vehicle]] : [], 0],
            ['vehicles', 'Delivery fleet register', 'vehicle', 'delivery-fleet-register.csv', 30, null, ['fleet'], [], 0],
        ];

        foreach ($files as [$in, $title, $type, $name, $issuedAgo, $expiresIn, $tags, $links, $extra]) {
            $parent = $tree[$in];
            $issued = today()->subDays($issuedAgo);
            $years = $this->store->inheritedRetention($parent);

            $document = Document::create([
                'folder_id' => $parent->id, 'title' => $title, 'document_type' => $type, 'tags' => $tags,
                'reference' => strtoupper(substr(md5($title), 0, 8)),
                'issued_on' => $issued, 'expires_on' => $expiresIn === null ? null : today()->addDays($expiresIn),
                'retention_years' => $years, 'retain_until' => $this->store->retainUntil($years, $issued->toDateString()),
                'current_version' => 1 + $extra, 'owner_id' => $admin->id, 'created_by' => $admin->id,
                'created_at' => $issued, 'updated_at' => $issued,
            ]);

            for ($v = 1; $v <= 1 + $extra; $v++) {
                [$contents, $mime] = $this->contents($name, $title, $v, $company->name);
                $this->store->storeContents($document, $contents, $name, $mime, $v, $admin);
            }

            foreach ($links as [$linkType, $linkId]) {
                DocumentLink::create(['document_id' => $document->id, 'attachable_type' => $linkType, 'attachable_id' => $linkId, 'created_by' => $admin->id]);
            }
        }

        auth()->forgetUser();
    }

    /** @return array{0: string, 1: string} the bytes and the media type of a small generated file */
    private function contents(string $name, string $title, int $version, string $company): array
    {
        $ext = pathinfo($name, PATHINFO_EXTENSION);
        $lines = [$company, $title, "Version {$version}", 'Generated demo document, '.now()->toDateString()];

        return match ($ext) {
            'csv' => ["registration,make,capacity_tonnes,driver\nT 512 DKL,Isuzu FRR,5,Ramadhani Ally\nT 418 DGE,Mitsubishi Canter,3,Saidi Hamza\nT 733 DMB,Tata 1518,10,Paulo Mlay\n", 'text/csv'],
            'txt' => [implode("\n", $lines)."\n", 'text/plain'],
            default => [$this->pdf($lines), 'application/pdf'],
        };
    }

    /** A minimal, valid one-page PDF showing the given lines, with a correct cross-reference table. */
    private function pdf(array $lines): string
    {
        $escape = fn (string $s) => str_replace(['\\', '(', ')'], ['\\\\', '\\(', '\\)'], $s);
        $text = "BT /F1 16 Tf 72 760 Td\n";
        foreach ($lines as $i => $line) {
            $text .= ($i ? "0 -26 Td\n" : '').'('.$escape($line).") Tj\n";
        }
        $text .= 'ET';

        $objects = [
            '<< /Type /Catalog /Pages 2 0 R >>',
            '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
            '<< /Length '.strlen($text)." >>\nstream\n{$text}\nendstream",
            '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        ];

        $pdf = "%PDF-1.4\n";
        $offsets = [];
        foreach ($objects as $i => $object) {
            $offsets[] = strlen($pdf);
            $pdf .= ($i + 1)." 0 obj\n{$object}\nendobj\n";
        }

        $xref = strlen($pdf);
        $pdf .= 'xref'."\n0 ".(count($objects) + 1)."\n0000000000 65535 f \n";
        foreach ($offsets as $offset) {
            $pdf .= sprintf("%010d 00000 n \n", $offset);
        }

        return $pdf.'trailer'."\n<< /Size ".(count($objects) + 1)." /Root 1 0 R >>\nstartxref\n{$xref}\n%%EOF\n";
    }
}
