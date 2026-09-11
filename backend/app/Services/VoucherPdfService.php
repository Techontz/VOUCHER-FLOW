<?php

namespace App\Services;

use App\Models\Voucher;
use App\Models\WorkflowStep;
use Barryvdh\DomPDF\Facade\Pdf;
use Barryvdh\DomPDF\PDF as PdfWrapper;
use Illuminate\Support\Facades\Storage;

/**
 * Renders the print-ready A4 voucher.
 *
 * The authorisation blocks are generated from the voucher's own workflow joined
 * against what was actually signed or approved, so the printed document matches
 * whatever route the tenant configured.
 */
class VoucherPdfService
{
    public function __construct(
        private readonly WorkflowEngine $engine,
        private readonly StatusPresenter $status,
        private readonly AmountFormatter $money,
    ) {}

    public function render(Voucher $voucher, string $locale = 'en'): PdfWrapper
    {
        $voucher->loadMissing([
            'company', 'department', 'requester', 'voucherType', 'paidBy',
            'workflow.steps', 'approvals.actor', 'attachments',
        ]);

        $status = $this->status->present($voucher);

        return Pdf::loadView('pdf.voucher', [
            'voucher' => $voucher,
            'company' => $voucher->company,
            'locale' => $locale,
            'typeLabel' => $voucher->voucherType?->label($locale) ?? 'Voucher',
            'statusLabel' => $locale === 'sw' ? $status['label_sw'] : $status['label'],
            'amountText' => $this->money->money((float) $voucher->amount, $voucher->currency),
            'signatories' => $this->signatories($voucher),
            'particulars' => $this->paymentParticulars($voucher),
            'isBank' => $voucher->isBank(),
            'fillerHeight' => $this->fillerHeight($voucher),
            'logo' => $this->logoPath($voucher),
            'fontPath' => storage_path('fonts'),
            'generatedAt' => now()->format('j M Y, H:i'),
            't' => $this->strings($locale),
        ])->setPaper('a4', 'portrait');
    }

    /**
     * How tall the blank ruled area under the line items should be.
     *
     * A voucher book leaves room to write, and a nearly empty page looks
     * unfinished — but DomPDF cannot measure text, so a fixed height either
     * wastes a third of a short voucher or pushes a long one onto page two.
     * This estimates the space the content above will take and gives the rest
     * to the rules, with a floor so the form never collapses entirely.
     */
    private function fillerHeight(Voucher $voucher): int
    {
        // ~68 characters to a line at this column width and type size.
        $descriptionLines = (int) ceil(mb_strlen((string) $voucher->description) / 68);
        $purposeLines = (int) ceil(mb_strlen((string) $voucher->purpose) / 44);

        // The right-hand column can be the taller of the two; once it passes
        // the left, it rather than the filler decides the page height.
        $panelRows = count($this->paymentParticulars($voucher)) + $voucher->attachments->count();

        $budget = 250
            - ($descriptionLines * 12)
            - (max(0, $purposeLines - 1) * 12)
            - (max(0, $panelRows - 9) * 14)
            - ($voucher->notes_to_approver ? 46 : 0);

        return max(80, min(250, $budget));
    }

    public function filename(Voucher $voucher): string
    {
        return $voucher->number.'.pdf';
    }

    /** @return array<int,array{label:string,name:?string,meta:string,signature:?string,stamp:?string}> */
    private function signatories(Voucher $voucher): array
    {
        $blocks = [];

        // The requester always prepares the voucher. Authorship, not assent —
        // so this block carries a name and no mark.
        $blocks[] = [
            'label' => 'Prepared by',
            'name' => $voucher->requester?->name,
            'meta' => trim(($voucher->requester?->job_title ?? '').' · '.($voucher->submitted_at?->format('j M Y') ?? 'Not submitted'), ' ·'),
            'signature' => null,
            'stamp' => null,
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

            $verb = match (true) {
                $decisive?->action === 'rejected' => 'Rejected by',
                $step->can_approve => 'Approved by',
                default => 'Signed by',
            };

            $blocks[] = [
                'label' => $verb.' ('.WorkflowStep::roleLabel($step->role).')',
                'name' => $actor?->actor_name,
                'meta' => $actor?->acted_at?->format('j M Y, H:i') ?? 'Pending',
                'signature' => $this->inlineSignature($signature),
                'stamp' => match (true) {
                    $decisive?->action === 'rejected' => 'rejected',
                    $decisive === null && $actor === null => null,
                    $step->can_approve => 'approved',
                    default => 'signed',
                },
            ];
        }

        // Payment closes the document. A voucher that has been approved but not
        // yet paid still prints this block, empty — the gap IS the information,
        // and a finance file wants to see that the money has not moved.
        if ($voucher->isPaid() || $voucher->isAwaitingPayment()) {
            $paid = $voucher->approvals->firstWhere('action', 'paid');

            $blocks[] = [
                'label' => 'Paid by',
                'name' => $voucher->paidBy?->name,
                'meta' => $voucher->isPaid()
                    ? trim(($voucher->payment_date?->format('j M Y') ?? '')
                        .($voucher->payment_reference ? ' · ref '.$voucher->payment_reference : ''), ' ·')
                    : 'Awaiting payment',
                'signature' => $this->inlineSignature($paid?->signature_data),
                'stamp' => $voucher->isPaid() ? 'paid' : null,
            ];
        }

        return $blocks;
    }

    /**
     * The right-hand panel: everything a payments clerk needs to move the money.
     * Bank and cash ask for different things, so each returns only its own.
     *
     * @return array<int,array{0:string,1:?string}>
     */
    private function paymentParticulars(Voucher $voucher): array
    {
        $rows = [
            ['Amount', $this->money->money((float) $voucher->amount, $voucher->currency)],
            ['Payment method', $voucher->payment_method],
            ['Voucher type', $voucher->voucherType?->name],
            ['Reference', $voucher->account_ref],
        ];

        if ($voucher->isBank()) {
            $rows = array_merge($rows, [
                ['Payee bank', $voucher->payee_bank],
                ['Account name', $voucher->payee_account_name],
                ['Account no.', $voucher->payee_account_number],
                ['Branch', $voucher->payee_bank_branch],
                ['Cheque no.', $voucher->cheque_number],
            ]);
        } else {
            $rows = array_merge($rows, [
                ['Cash float', $voucher->cash_float],
                ['Received by', $voucher->received_by],
            ]);
        }

        if ($voucher->isPaid()) {
            $rows[] = ['Paid on', $voucher->payment_date?->format('j M Y')];
            $rows[] = ['Payment ref.', $voucher->payment_reference];
        }

        return array_values(array_filter($rows, fn ($row) => filled($row[1])));
    }

    /** DomPDF renders base64 data URIs directly; anything else is dropped. */
    private function inlineSignature(?string $data): ?string
    {
        if (! $data || ! str_starts_with($data, 'data:image/')) {
            return null;
        }

        return $data;
    }

    private function logoPath(Voucher $voucher): ?string
    {
        $path = $voucher->company?->logo_path;

        if (! $path) {
            return null;
        }

        $absolute = Storage::disk('public')->path($path);

        return is_readable($absolute) ? $absolute : null;
    }

    private function strings(string $locale): array
    {
        $en = [
            'date' => 'Date',
            'department' => 'Department',
            'payee' => 'Payee',
            'requestedBy' => 'Requested by',
            'paymentMethod' => 'Payment method',
            'reference' => 'Reference',
            'category' => 'Category',
            'costCentre' => 'Cost centre',
            'paymentPurpose' => 'Payment purpose',
            'amountWords' => 'Amount in words',
            'totalPayable' => 'Total payable',
            'authorisation' => 'Authorisation',
            'attachments' => 'Supporting documents',
            'verificationCode' => 'Verification code',
            'original' => 'Original · page 1 of 1',
            'generated' => 'Generated',
            'approved' => 'Approved',
            'rejected' => 'Rejected',
        ];

        $sw = [
            'date' => 'Tarehe',
            'department' => 'Idara',
            'payee' => 'Mlipwaji',
            'requestedBy' => 'Imeombwa na',
            'paymentMethod' => 'Njia ya malipo',
            'reference' => 'Kumbukumbu',
            'category' => 'Kundi',
            'costCentre' => 'Kituo cha gharama',
            'paymentPurpose' => 'Madhumuni ya malipo',
            'amountWords' => 'Kiasi kwa maneno',
            'totalPayable' => 'Jumla inayolipwa',
            'authorisation' => 'Uidhinishaji',
            'attachments' => 'Nyaraka za uthibitisho',
            'verificationCode' => 'Namba ya uthibitisho',
            'original' => 'Nakala halisi · ukurasa 1 wa 1',
            'generated' => 'Imetengenezwa',
            'approved' => 'Imeidhinishwa',
            'rejected' => 'Imekataliwa',
        ];

        return $locale === 'sw' ? $sw : $en;
    }
}
