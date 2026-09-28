<?php

namespace App\Services;

use App\Models\Company;
use App\Models\Voucher;
use App\Models\WorkflowStep;
use App\Support\VoucherTemplates;
use BaconQrCode\Common\ErrorCorrectionLevel;
use BaconQrCode\Encoder\Encoder;
use Illuminate\Support\Facades\Storage;

/**
 * The printed voucher as plain data, and its rendering.
 *
 * Every voucher template reads exactly the array built here — never the
 * models — so ten designs share one definition of what a voucher says. A real
 * voucher and the sample shown when choosing a design go through the same
 * shape, which is what makes the preview an honest picture of the document.
 *
 * The same HTML serves two masters: DomPDF (mode "pdf") for print and
 * download, and the browser (mode "html") for the on-screen document. That is
 * why the templates are built from tables: DomPDF has no flexbox or grid.
 */
class VoucherDocument
{
    public function __construct(
        private readonly WorkflowEngine $engine,
        private readonly StatusPresenter $status,
        private readonly AmountFormatter $money,
    ) {}

    /** The design a voucher renders in: its frozen snapshot, else the company's current one. */
    public function templateFor(Voucher $voucher): string
    {
        return VoucherTemplates::resolve($voucher->voucher_template ?: $voucher->company?->voucher_template);
    }

    public function render(Voucher $voucher, string $locale = 'en', string $mode = 'pdf', ?string $template = null): string
    {
        $template = VoucherTemplates::resolve($template ?? $this->templateFor($voucher));

        return view(VoucherTemplates::view($template), [
            'doc' => $this->fromVoucher($voucher, $locale, $mode, $template),
        ])->render();
    }

    /**
     * The sample voucher shown when a design is being chosen.
     *
     * @param  array<string, mixed>  $brand  company fields to show instead of the sample company's
     */
    public function renderSample(string $template, array $brand = [], string $locale = 'en', string $mode = 'html'): string
    {
        $template = VoucherTemplates::resolve($template);

        return view(VoucherTemplates::view($template), [
            'doc' => $this->sample($template, $brand, $locale, $mode),
        ])->render();
    }

    /** @return array<string, mixed> */
    public function fromVoucher(Voucher $voucher, string $locale, string $mode, string $template): array
    {
        $voucher->loadMissing([
            'company', 'department', 'requester', 'voucherType', 'paidBy',
            'workflow.steps', 'approvals.actor', 'attachments',
        ]);

        $company = $voucher->company;
        $t = self::strings($locale);
        $status = $this->status->present($voucher);
        $isBank = $voucher->isBank();

        return [
            'mode' => $mode,
            'template' => $template,
            'locale' => $locale,
            't' => $t,
            'brand' => self::palette($company?->primary_color, $company?->secondary_color),
            'company' => $this->companyBlock($company, $mode),
            'voucher' => [
                'number' => $voucher->number,
                'type_label' => $voucher->voucherType?->label($locale) ?? $t['paymentVoucher'],
                'kind' => $isBank ? 'bank' : 'cash',
                'kind_label' => $isBank ? $t['bankVoucher'] : $t['cashVoucher'],
                'date' => $voucher->voucher_date?->format('j M Y') ?? '—',
                'department' => $voucher->department?->name ?: '—',
                'cost_centre' => $voucher->cost_centre,
                'requester' => $voucher->requester?->name ?? '—',
                'requester_title' => $voucher->requester?->job_title,
                'category' => $voucher->category ?: '—',
                'payee' => $voucher->payee ?: '—',
                'purpose' => $voucher->purpose,
                'description' => $voucher->description,
                'reference' => $voucher->account_ref,
                'currency' => $voucher->currency,
                'amount' => (float) $voucher->amount > 0 ? number_format((float) $voucher->amount) : '—',
                'amount_text' => $this->money->money((float) $voucher->amount, $voucher->currency),
                'amount_words' => (float) $voucher->amount > 0
                    ? ($voucher->amount_in_words ?: $this->money->money((float) $voucher->amount, $voucher->currency))
                    : '—',
                'payment_method' => $voucher->payment_method ?: ($isBank ? $t['bank'] : $t['cash']),
                'remarks' => $voucher->notes_to_approver,
                'verification_code' => $voucher->verification_code,
                'status' => $voucher->status,
                'status_label' => $locale === 'sw' ? $status['label_sw'] : $status['label'],
                'submitted' => $voucher->submitted_at?->format('j M Y'),
            ],
            'payment' => $payment = $this->payment($voucher, $t),
            'particulars' => self::particulars($payment, $isBank ? 'bank' : 'cash', $t),
            'attachments' => $voucher->attachments->map(fn ($f) => $f->original_name ?? $f->name)->values()->all(),
            'signatories' => $this->signatories($voucher, $t),
            'mark' => $this->mark($voucher, $t),
            'qr' => self::qr($voucher->verification_code),
            'generated_at' => now()->format('j M Y, H:i'),
            'filler' => $this->fillerHeight($voucher),
        ];
    }

    /**
     * @param  array<string, mixed>  $brand
     * @return array<string, mixed>
     */
    public function sample(string $template, array $brand, string $locale, string $mode): array
    {
        $t = self::strings($locale);
        $name = trim((string) ($brand['name'] ?? '')) ?: 'Kilimanjaro Logistics Ltd';
        $isSampleCompany = trim((string) ($brand['name'] ?? '')) === '';

        $lines = array_values(array_filter([
            $brand['address'] ?? ($isSampleCompany ? 'Plot 12, Nyerere Road, Dar es Salaam' : null),
            implode(' · ', array_filter([
                $brand['phone'] ?? ($isSampleCompany ? '+255 22 211 0000' : null),
                $brand['email'] ?? ($isSampleCompany ? 'accounts@kilimanjarologistics.co.tz' : null),
            ])) ?: null,
            implode(' · ', array_filter([
                $brand['website'] ?? null,
                ($brand['tin'] ?? ($isSampleCompany ? '123-456-789' : null)) ? 'TIN '.($brand['tin'] ?? '123-456-789') : null,
            ])) ?: null,
        ]));

        $sig = fn (string $path) => 'data:image/svg+xml;base64,'.base64_encode(
            '<svg xmlns="http://www.w3.org/2000/svg" width="160" height="50" viewBox="0 0 160 50">'
            .'<path d="'.$path.'" fill="none" stroke="#1d2b4f" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
        );

        return [
            'mode' => $mode,
            'template' => $template,
            'locale' => $locale,
            't' => $t,
            'brand' => self::palette($brand['primary_color'] ?? null, $brand['secondary_color'] ?? null),
            'company' => [
                'name' => $name,
                'lines' => $lines,
                'logo' => $brand['logo'] ?? null,
                'initial' => mb_strtoupper(mb_substr($name, 0, 1)),
                'header_text' => $brand['voucher_header_text'] ?? null,
                'footer_text' => $brand['voucher_footer_text'] ?? $t['defaultFooter'],
                'bank' => [
                    'name' => 'CRDB Bank PLC',
                    'account_name' => $name,
                    'account_number' => '0150 2345 6789 00',
                    'branch' => 'Azikiwe',
                ],
            ],
            'voucher' => [
                'number' => 'PV-2026-00124',
                'type_label' => $t['paymentVoucher'],
                'kind' => 'bank',
                'kind_label' => $t['bankVoucher'],
                'date' => '24 Sep 2026',
                'department' => 'Procurement',
                'cost_centre' => 'CC-PRO',
                'requester' => 'Frank Kessy',
                'requester_title' => 'Procurement Officer',
                'category' => 'Logistics',
                'payee' => 'Puma Energy Tanzania Ltd',
                'purpose' => 'Vehicle fuel expenses',
                'description' => 'Diesel for delivery trucks T 123 ABC and T 456 DEF on the Dar es Salaam – Morogoro route, 22–26 September 2026.',
                'reference' => 'INV-PE-88213',
                'currency' => 'TZS',
                'amount' => '450,000',
                'amount_text' => 'TZS 450,000',
                'amount_words' => $locale === 'sw'
                    ? 'Shilingi laki nne na elfu hamsini tu'
                    : 'Four hundred and fifty thousand shillings only',
                'payment_method' => 'Bank Transfer',
                'remarks' => 'Fuel receipts from both trucks are attached.',
                'verification_code' => 'VF-7Q2K-91XD',
                'status' => 'paid',
                'status_label' => $locale === 'sw' ? 'Imelipwa' : 'Paid',
                'submitted' => '24 Sep 2026',
            ],
            'payment' => $payment = [
                'amount' => 'TZS 450,000',
                'currency' => 'TZS',
                'method' => 'Bank Transfer',
                'type' => $t['paymentVoucher'],
                'reference' => 'INV-PE-88213',
                'bank' => 'CRDB Bank PLC',
                'account_name' => 'Puma Energy Tanzania Ltd',
                'account_no' => '0150 3905 6950 0',
                'branch' => 'Tower Branch',
                'cheque_no' => null,
                'cash_float' => null,
                'received_by' => null,
                'amount_paid' => null,
                'balance' => null,
                'paid_on' => '26 Sep 2026',
                'payment_ref' => 'TRF-55820931',
            ],
            'particulars' => self::particulars($payment, 'bank', $t),
            'attachments' => ['Fuel receipt T 123 ABC.pdf', 'Fuel receipt T 456 DEF.pdf', 'Trip log 22–26 Sep.xlsx'],
            'signatories' => [
                ['caption' => $t['preparedBy'], 'role' => $t['requester'], 'name' => 'Frank Kessy', 'meta' => 'Procurement Officer · 24 Sep 2026', 'date' => '24 Sep 2026', 'signature' => null, 'stamp' => null, 'state' => 'done'],
                ['caption' => $t['signedBy'], 'role' => 'HOD', 'name' => 'Joseph Mrisho', 'meta' => '24 Sep 2026, 14:10', 'date' => '24 Sep 2026, 14:10', 'signature' => $sig('M6 34 C 18 10, 26 44, 38 24 S 58 12, 62 30 S 84 40, 96 18 L 110 30 C 120 36, 136 20, 152 26'), 'stamp' => 'signed', 'state' => 'done'],
                ['caption' => $t['approvedBy'], 'role' => 'CEO', 'name' => 'Emmanuel Massawe', 'meta' => '25 Sep 2026, 09:42', 'date' => '25 Sep 2026, 09:42', 'signature' => $sig('M8 30 C 20 6, 30 40, 44 20 C 52 8, 60 40, 72 28 S 96 8, 108 30 S 138 34, 150 16'), 'stamp' => 'approved', 'state' => 'done'],
                ['caption' => $t['paidBy'], 'role' => $t['cashier'], 'name' => 'Mwajuma Hamisi', 'meta' => '26 Sep 2026 · ref TRF-55820931', 'date' => '26 Sep 2026', 'signature' => $sig('M10 28 C 24 12, 34 38, 46 24 S 70 30, 80 18 C 92 6, 100 38, 116 26 S 140 20, 150 28'), 'stamp' => 'paid', 'state' => 'done'],
            ],
            'qr' => self::qr('VF-7Q2K-91XD'),
            'mark' => null,
            'generated_at' => '26 Sep 2026, 11:05',
            'filler' => 120,
        ];
    }

    /**
     * The company's colours, with the tints and contrasting text the designs
     * need. Templates never hard-code a brand colour: everything that carries
     * the company's identity comes from here.
     *
     * @return array<string, string>
     */
    public static function palette(?string $primary, ?string $secondary): array
    {
        $primary = self::hex($primary) ?? '#2E3192';
        $secondary = self::hex($secondary) ?? '#0B1D3A';

        return [
            'primary' => $primary,
            'secondary' => $secondary,
            'on_primary' => self::readableOn($primary),
            'on_secondary' => self::readableOn($secondary),
            'tint' => self::mix($primary, 0.07),
            'tint_strong' => self::mix($primary, 0.16),
            'secondary_tint' => self::mix($secondary, 0.07),
            // A brand colour dark enough to set type in on white paper.
            'ink' => self::luminance($primary) > 0.45 ? self::darken($primary, 0.45) : $primary,
        ];
    }

    /** @return array{name: string, lines: list<string>, logo: ?string, initial: string, header_text: ?string, footer_text: string, bank: ?array} */
    private function companyBlock(?Company $company, string $mode): array
    {
        $name = $company?->documentName() ?? 'VouchFlow';

        return [
            'name' => $name,
            'lines' => array_values(array_filter([
                $company?->address,
                collect([$company?->phone, $company?->email])->filter()->implode(' · ') ?: null,
                collect([$company?->website, $company?->tin ? 'TIN '.$company->tin : null])->filter()->implode(' · ') ?: null,
            ])),
            'logo' => $this->logoSource($company, $mode),
            'initial' => mb_strtoupper(mb_substr($name, 0, 1)),
            'header_text' => $company?->voucher_header_text,
            'footer_text' => $company?->voucher_footer_text ?: self::strings($company?->locale ?? 'en')['defaultFooter'],
            'bank' => $company?->bank_name ? [
                'name' => $company->bank_name,
                'account_name' => $company->bank_account_name,
                'account_number' => $company->bank_account_number,
                'branch' => $company->bank_branch,
            ] : null,
        ];
    }

    /** DomPDF reads the file from disk; a browser needs its URL. */
    private function logoSource(?Company $company, string $mode): ?string
    {
        $path = $company?->logo_path;

        if (! $path) {
            return null;
        }

        if ($mode === 'html') {
            return $company->logoUrl();
        }

        $absolute = Storage::disk('public')->path($path);

        return is_readable($absolute) ? $absolute : null;
    }

    /** @return list<array{caption: string, role: string, name: ?string, meta: string, date: ?string, signature: ?string, stamp: ?string, state: string}> */
    private function signatories(Voucher $voucher, array $t): array
    {
        $blocks = [];

        // The requester always prepares the voucher. Authorship, not assent —
        // so this block carries a name and no mark.
        $blocks[] = [
            'caption' => $t['preparedBy'],
            'role' => $t['requester'],
            'name' => $voucher->requester?->name,
            'meta' => trim(($voucher->requester?->job_title ?? '').' · '.($voucher->submitted_at?->format('j M Y') ?? $t['notSubmitted']), ' ·'),
            'date' => $voucher->submitted_at?->format('j M Y'),
            'signature' => null,
            'stamp' => null,
            'state' => $voucher->submitted_at ? 'done' : 'pending',
        ];

        $closed = $voucher->isTerminal();

        foreach ($this->engine->approvalSteps($voucher) as $step) {
            $events = $voucher->approvals->where('step_position', $step->position);

            // A closed voucher prints only the marks it actually collected. The
            // company's workflow may have been edited since; a completed document
            // must not sprout a "pending" block for a step it never passed through.
            if ($closed && $events->isEmpty()) {
                continue;
            }

            $signature = $events->firstWhere('action', 'signed')?->signature_data;
            $decisive = $events->last(fn ($a) => in_array($a->action, ['approved', 'rejected', 'forwarded'], true));
            $actor = $decisive ?? $events->last();

            $caption = match (true) {
                $decisive?->action === 'rejected' => $t['rejectedBy'],
                (bool) $step->can_approve => $t['approvedBy'],
                default => $t['signedBy'],
            };

            $blocks[] = [
                'caption' => $caption,
                'role' => WorkflowStep::roleLabel($step->role),
                'name' => $actor?->actor_name,
                'meta' => $actor?->acted_at?->format('j M Y, H:i')
                    ?? ($step->can_approve ? $t['awaitingApproval'] : $t['awaitingSignature']),
                'date' => $actor?->acted_at?->format('j M Y, H:i'),
                'signature' => self::inlineImage($signature),
                'stamp' => match (true) {
                    $decisive?->action === 'rejected' => 'rejected',
                    $decisive === null && $actor === null => null,
                    (bool) $step->can_approve => 'approved',
                    default => 'signed',
                },
                'state' => match (true) {
                    $decisive?->action === 'rejected' => 'rejected',
                    $actor !== null => 'done',
                    default => 'pending',
                },
            ];
        }

        // Payment closes the document. A voucher that has been approved but not
        // yet paid still prints this block, empty — the gap IS the information.
        // Every voucher still alive shows where payment will be recorded; only
        // a rejected or cancelled one has no payment to come.
        if (! in_array($voucher->status, [Voucher::STATUS_REJECTED, Voucher::STATUS_CANCELLED], true)) {
            $paid = $voucher->approvals->firstWhere('action', 'paid');

            $blocks[] = [
                'caption' => $voucher->isCash() ? $t['paidReceivedBy'] : $t['paidBy'],
                'role' => $t['cashier'],
                'name' => $voucher->paidBy?->name,
                'meta' => $voucher->isPaid()
                    ? trim(($voucher->payment_date?->format('j M Y') ?? '')
                        .($voucher->payment_reference ? ' · ref '.$voucher->payment_reference : ''), ' ·')
                    : $t['awaitingPayment'],
                'date' => $voucher->payment_date?->format('j M Y'),
                'signature' => self::inlineImage($paid?->signature_data),
                'stamp' => $voucher->isPaid() ? 'paid' : null,
                'state' => $voucher->isPaid() ? 'done' : 'pending',
            ];
        }

        return $blocks;
    }

    /**
     * Everything a payments clerk needs to move the money, by name, so each
     * design can place every field where it wants. Nothing is dropped for
     * being empty: an unfilled field prints as a blank (—), the way a form does.
     *
     * @return array<string, ?string>
     */
    private function payment(Voucher $voucher, array $t): array
    {
        $partlyPaid = (float) $voucher->amount_paid > 0 && ! $voucher->isPaid();

        return [
            'amount' => (float) $voucher->amount > 0 ? $this->money->money((float) $voucher->amount, $voucher->currency) : null,
            'currency' => $voucher->currency,
            'method' => $voucher->payment_method ?: ($voucher->isBank() ? $t['bank'] : $t['cash']),
            'type' => $voucher->voucherType?->name,
            'reference' => $voucher->account_ref,
            'bank' => $voucher->payee_bank,
            'account_name' => $voucher->payee_account_name,
            'account_no' => $voucher->payee_account_number,
            'branch' => $voucher->payee_bank_branch,
            'cheque_no' => $voucher->cheque_number,
            'cash_float' => $voucher->cash_float,
            'received_by' => $voucher->received_by,
            'amount_paid' => $partlyPaid ? $this->money->money((float) $voucher->amount_paid, $voucher->currency) : null,
            'balance' => $partlyPaid ? $this->money->money($voucher->balance(), $voucher->currency) : null,
            'paid_on' => $voucher->isPaid() ? $voucher->payment_date?->format('j M Y') : null,
            'payment_ref' => $voucher->payment_reference,
        ];
    }

    /**
     * The payment fields as labelled rows, in reading order. The core rows are
     * always present; the rest appear once they carry something.
     *
     * @param  array<string, ?string>  $p
     * @return list<array{0: string, 1: string}>
     */
    public static function particulars(array $p, string $kind, array $t): array
    {
        $always = [
            [$t['amount'], $p['amount']],
            [$t['currency'], $p['currency']],
            [$t['paymentMethod'], $p['method']],
            [$t['voucherType'], $p['type']],
            [$t['reference'], $p['reference']],
        ];

        $always = array_merge($always, $kind === 'bank'
            ? [[$t['payeeBank'], $p['bank']], [$t['accountName'], $p['account_name']], [$t['accountNo'], $p['account_no']], [$t['branch'], $p['branch']]]
            : [[$t['cashFloat'], $p['cash_float']], [$t['receivedBy'], $p['received_by']]]);

        $optional = array_filter([
            [$t['chequeNo'], $p['cheque_no']],
            [$t['amountPaid'], $p['amount_paid']],
            [$t['balance'], $p['balance']],
            [$t['paidOn'], $p['paid_on']],
            [$t['paymentRef'], $p['payment_ref']],
        ], fn ($row) => filled($row[1]));

        return array_map(
            fn ($row) => [$row[0], filled($row[1]) ? (string) $row[1] : '—'],
            array_values(array_merge($always, $optional)),
        );
    }

    /**
     * The verification code as a real, scannable QR matrix. Drawn as a table
     * of cells rather than an image, so DomPDF and the browser render the same
     * crisp squares with nothing to fetch.
     *
     * @return ?array{code: string, size: int, cells: list<list<bool>>}
     */
    public static function qr(?string $code): ?array
    {
        if (! $code) {
            return null;
        }

        $matrix = Encoder::encode($code, ErrorCorrectionLevel::M())->getMatrix();
        $size = $matrix->getWidth();
        $cells = [];

        for ($y = 0; $y < $size; $y++) {
            $row = [];
            for ($x = 0; $x < $size; $x++) {
                $row[] = $matrix->get($x, $y) === 1;
            }
            $cells[] = $row;
        }

        return ['code' => $code, 'size' => $size, 'cells' => $cells];
    }

    /** The large diagonal mark a settled document carries. */
    private function mark(Voucher $voucher, array $t): ?array
    {
        return match ($voucher->status) {
            Voucher::STATUS_PAID => ['kind' => 'paid', 'label' => $t['markPaid'], 'date' => $voucher->payment_date?->format('j M Y')],
            Voucher::STATUS_REJECTED => ['kind' => 'rejected', 'label' => $t['markRejected'], 'date' => $voucher->rejected_at?->format('j M Y')],
            Voucher::STATUS_CANCELLED => ['kind' => 'cancelled', 'label' => $t['markCancelled'], 'date' => null],
            default => null,
        };
    }

    /**
     * How tall the blank ruled area under the line items should be in the
     * classic design. DomPDF cannot measure text, so this estimates the space
     * the content above will take and gives the rest to the rules.
     */
    private function fillerHeight(Voucher $voucher): int
    {
        $descriptionLines = (int) ceil(mb_strlen((string) $voucher->description) / 68);
        $purposeLines = (int) ceil(mb_strlen((string) $voucher->purpose) / 44);
        $panelRows = 11 + $voucher->attachments->count();

        $budget = 250
            - ($descriptionLines * 12)
            - (max(0, $purposeLines - 1) * 12)
            - (max(0, $panelRows - 9) * 14)
            - ($voucher->notes_to_approver ? 46 : 0);

        return max(80, min(250, $budget));
    }

    /** Only embedded images render — DomPDF must never fetch a remote URL. */
    private static function inlineImage(?string $data): ?string
    {
        return $data && str_starts_with($data, 'data:image/') ? $data : null;
    }

    private static function hex(?string $value): ?string
    {
        return $value && preg_match('/^#[0-9a-fA-F]{6}$/', $value) ? strtoupper($value) : null;
    }

    /** @return array{0: int, 1: int, 2: int} */
    private static function rgb(string $hex): array
    {
        return [hexdec(substr($hex, 1, 2)), hexdec(substr($hex, 3, 2)), hexdec(substr($hex, 5, 2))];
    }

    /** The colour laid over white paper at the given strength. */
    private static function mix(string $hex, float $amount): string
    {
        [$r, $g, $b] = self::rgb($hex);
        $c = fn (int $v) => (int) round(255 - (255 - $v) * $amount);

        return sprintf('#%02X%02X%02X', $c($r), $c($g), $c($b));
    }

    private static function darken(string $hex, float $amount): string
    {
        [$r, $g, $b] = self::rgb($hex);
        $c = fn (int $v) => (int) round($v * (1 - $amount));

        return sprintf('#%02X%02X%02X', $c($r), $c($g), $c($b));
    }

    private static function luminance(string $hex): float
    {
        [$r, $g, $b] = array_map(function (int $v) {
            $s = $v / 255;

            return $s <= 0.03928 ? $s / 12.92 : (($s + 0.055) / 1.055) ** 2.4;
        }, self::rgb($hex));

        return 0.2126 * $r + 0.7152 * $g + 0.0722 * $b;
    }

    private static function readableOn(string $hex): string
    {
        return self::luminance($hex) > 0.5 ? '#0B1220' : '#FFFFFF';
    }

    /** @return array<string, string> */
    public static function strings(string $locale): array
    {
        $en = [
            'currency' => 'Currency',
            'awaitingSignature' => 'Awaiting signature',
            'awaitingApproval' => 'Awaiting approval',
            'scanToVerify' => 'Scan to verify',
            'paymentVoucher' => 'Payment voucher',
            'bankVoucher' => 'Bank voucher',
            'cashVoucher' => 'Cash voucher',
            'voucherNo' => 'Voucher no.',
            'date' => 'Date',
            'department' => 'Department',
            'costCentre' => 'Cost centre',
            'payee' => 'Payee',
            'beneficiary' => 'Beneficiary',
            'requestedBy' => 'Requested by',
            'requester' => 'Requester',
            'employee' => 'Employee',
            'category' => 'Category',
            'purpose' => 'Purpose',
            'description' => 'Description',
            'particulars' => 'Particulars',
            'amount' => 'Amount',
            'paymentMethod' => 'Payment method',
            'bank' => 'Bank transfer',
            'cash' => 'Cash',
            'voucherType' => 'Voucher type',
            'reference' => 'Reference',
            'payeeBank' => 'Payee bank',
            'accountName' => 'Account name',
            'accountNo' => 'Account no.',
            'branch' => 'Branch',
            'chequeNo' => 'Cheque no.',
            'cashFloat' => 'Cash float',
            'receivedBy' => 'Received by',
            'amountPaid' => 'Paid so far',
            'balance' => 'Balance',
            'paidOn' => 'Paid on',
            'paymentRef' => 'Payment ref.',
            'amountWords' => 'Amount in words',
            'totalPayable' => 'Total payable',
            'paymentParticulars' => 'Payment particulars',
            'paymentDetails' => 'Payment details',
            'drawnOn' => 'Drawn on',
            'authorisation' => 'Authorisation',
            'approvals' => 'Approvals',
            'approvalTrail' => 'Approval trail',
            'finance' => 'Finance',
            'financeUse' => 'For finance office use only',
            'requestDetails' => 'Request details',
            'expenseDetails' => 'Expense details',
            'attachments' => 'Supporting documents',
            'noneAttached' => 'None attached',
            'remarks' => 'Remarks',
            'verificationCode' => 'Verification code',
            'original' => 'Original · page 1 of 1',
            'generated' => 'Generated',
            'status' => 'Status',
            'signature' => 'Signature',
            'name' => 'Name',
            'role' => 'Role',
            'preparedBy' => 'Prepared by',
            'signedBy' => 'Signed by',
            'approvedBy' => 'Approved by',
            'rejectedBy' => 'Rejected by',
            'paidBy' => 'Paid by',
            'paidReceivedBy' => 'Paid / received by',
            'cashier' => 'Cashier',
            'pending' => 'Pending',
            'notSubmitted' => 'Not submitted',
            'awaitingPayment' => 'Awaiting payment',
            'signed' => 'Signed',
            'approved' => 'Approved',
            'paid' => 'Paid',
            'rejected' => 'Rejected',
            'markPaid' => 'Paid',
            'markRejected' => 'Rejected',
            'markCancelled' => 'Cancelled',
            'defaultFooter' => 'This voucher is valid only with the authorisations above.',
        ];

        $sw = [
            'currency' => 'Sarafu',
            'awaitingSignature' => 'Inasubiri sahihi',
            'awaitingApproval' => 'Inasubiri idhini',
            'scanToVerify' => 'Changanua kuthibitisha',
            'paymentVoucher' => 'Vocha ya malipo',
            'bankVoucher' => 'Vocha ya benki',
            'cashVoucher' => 'Vocha ya fedha taslimu',
            'voucherNo' => 'Namba ya vocha',
            'date' => 'Tarehe',
            'department' => 'Idara',
            'costCentre' => 'Kituo cha gharama',
            'payee' => 'Mlipwaji',
            'beneficiary' => 'Mnufaika',
            'requestedBy' => 'Imeombwa na',
            'requester' => 'Mwombaji',
            'employee' => 'Mfanyakazi',
            'category' => 'Kundi',
            'purpose' => 'Madhumuni',
            'description' => 'Maelezo',
            'particulars' => 'Maelezo ya malipo',
            'amount' => 'Kiasi',
            'paymentMethod' => 'Njia ya malipo',
            'bank' => 'Uhamisho wa benki',
            'cash' => 'Fedha taslimu',
            'voucherType' => 'Aina ya vocha',
            'reference' => 'Kumbukumbu',
            'payeeBank' => 'Benki ya mlipwaji',
            'accountName' => 'Jina la akaunti',
            'accountNo' => 'Namba ya akaunti',
            'branch' => 'Tawi',
            'chequeNo' => 'Namba ya hundi',
            'cashFloat' => 'Mfuko wa fedha',
            'receivedBy' => 'Imepokelewa na',
            'amountPaid' => 'Kilicholipwa',
            'balance' => 'Salio',
            'paidOn' => 'Ililipwa',
            'paymentRef' => 'Kumb. ya malipo',
            'amountWords' => 'Kiasi kwa maneno',
            'totalPayable' => 'Jumla inayolipwa',
            'paymentParticulars' => 'Taarifa za malipo',
            'paymentDetails' => 'Taarifa za malipo',
            'drawnOn' => 'Kutoka akaunti',
            'authorisation' => 'Uidhinishaji',
            'approvals' => 'Idhini',
            'approvalTrail' => 'Mfuatano wa idhini',
            'finance' => 'Fedha',
            'financeUse' => 'Kwa matumizi ya ofisi ya fedha tu',
            'requestDetails' => 'Taarifa za ombi',
            'expenseDetails' => 'Taarifa za gharama',
            'attachments' => 'Nyaraka za uthibitisho',
            'noneAttached' => 'Hakuna kiambatisho',
            'remarks' => 'Maoni',
            'verificationCode' => 'Namba ya uthibitisho',
            'original' => 'Nakala halisi · ukurasa 1 wa 1',
            'generated' => 'Imetengenezwa',
            'status' => 'Hali',
            'signature' => 'Sahihi',
            'name' => 'Jina',
            'role' => 'Wadhifa',
            'preparedBy' => 'Imeandaliwa na',
            'signedBy' => 'Imesainiwa na',
            'approvedBy' => 'Imeidhinishwa na',
            'rejectedBy' => 'Imekataliwa na',
            'paidBy' => 'Imelipwa na',
            'paidReceivedBy' => 'Imelipwa / kupokelewa na',
            'cashier' => 'Keshia',
            'pending' => 'Inasubiri',
            'notSubmitted' => 'Haijawasilishwa',
            'awaitingPayment' => 'Inasubiri malipo',
            'signed' => 'Imesainiwa',
            'approved' => 'Imeidhinishwa',
            'paid' => 'Imelipwa',
            'rejected' => 'Imekataliwa',
            'markPaid' => 'Imelipwa',
            'markRejected' => 'Imekataliwa',
            'markCancelled' => 'Imefutwa',
            'defaultFooter' => 'Vocha hii ni halali tu ikiwa na idhini zilizo hapo juu.',
        ];

        return $locale === 'sw' ? $sw : $en;
    }
}
