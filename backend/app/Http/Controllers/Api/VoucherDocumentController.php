<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Voucher;
use App\Services\AuditLogger;
use App\Services\VoucherPdfService;
use App\Services\VoucherVisibility;
use App\Services\WorkflowEngine;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

/**
 * The printed voucher. Available at every workflow stage, not only once approved,
 * subject to the step's print/download grants.
 */
class VoucherDocumentController extends Controller
{
    public function __construct(
        private readonly VoucherPdfService $pdf,
        private readonly VoucherVisibility $visibility,
        private readonly WorkflowEngine $engine,
        private readonly AuditLogger $audit,
    ) {}

    /** Inline, for the browser's own print dialog and the mobile preview. */
    public function stream(Request $request, Voucher $voucher)
    {
        $this->authorizeDocument($request, $voucher, 'print');

        return $this->pdf->render($voucher, app()->getLocale())
            ->stream($this->pdf->filename($voucher));
    }

    public function download(Request $request, Voucher $voucher)
    {
        $this->authorizeDocument($request, $voucher, 'download');

        $this->audit->log('voucher.downloaded', "Downloaded PDF for {$voucher->number}", $voucher);

        return $this->pdf->render($voucher, app()->getLocale())
            ->download($this->pdf->filename($voucher));
    }

    private function authorizeDocument(Request $request, Voucher $voucher, string $capability): void
    {
        $gate = Gate::forUser($request->user());

        if ($gate->denies('view', $voucher)) {
            throw new AccessDeniedHttpException('This voucher belongs to another part of the business.');
        }

        if ($gate->denies($capability, $voucher)) {
            throw new AccessDeniedHttpException('Your current step does not allow that.');
        }
    }
}
