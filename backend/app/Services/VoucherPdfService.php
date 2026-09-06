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
            'company', 'department', 'requester', 'voucherType',
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
            'logo' => $this->logoPath($voucher),
            'fontPath' => storage_path('fonts'),
            'generatedAt' => now()->format('j M Y, H:i'),
            't' => $this->strings($locale),
        ])->setPaper('a4', 'portrait');
    }

    public function filename(Voucher $voucher): string
    {
        return $voucher->number.'.pdf';
    }

    /** @return array<int,array{label:string,name:?string,meta:string,signature:?string}> */
    private function signatories(Voucher $voucher): array
    {
        $blocks = [];

        // The requester always prepares the voucher.
        $blocks[] = [
            'label' => 'Prepared by',
            'name' => $voucher->requester?->name,
            'meta' => trim(($voucher->requester?->job_title ?? '').' · '.($voucher->submitted_at?->format('j M Y') ?? 'Not submitted'), ' ·'),
            'signature' => null,
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
            ];
        }

        return $blocks;
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
