<?php

namespace App\Services;

use App\Models\Voucher;
use Barryvdh\DomPDF\Facade\Pdf;
use Barryvdh\DomPDF\PDF as PdfWrapper;

/**
 * Renders the print-ready A4 voucher in the design the voucher uses.
 *
 * The document itself — its data and its design — comes from VoucherDocument,
 * so the PDF, the on-screen document and the printout cannot disagree.
 */
class VoucherPdfService
{
    public function __construct(private readonly VoucherDocument $document) {}

    public function render(Voucher $voucher, string $locale = 'en'): PdfWrapper
    {
        return Pdf::loadHTML($this->document->render($voucher, $locale, 'pdf'))
            ->setPaper('a4', 'portrait');
    }

    public function filename(Voucher $voucher): string
    {
        return $voucher->number.'.pdf';
    }
}
