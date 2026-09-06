<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Voucher;
use App\Services\AuditLogger;
use App\Services\VoucherPdfService;
use App\Services\VoucherVisibility;
use App\Services\WorkflowEngine;
use Illuminate\Http\Request;
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
        $user = $request->user();

        $visible = $this->visibility
            ->apply(Voucher::query()->whereKey($voucher->id), $user)
            ->exists();

        if (! $visible) {
            throw new AccessDeniedHttpException('This voucher belongs to another part of the business.');
        }

        if (! ($this->engine->availableActions($user, $voucher)[$capability] ?? false)) {
            throw new AccessDeniedHttpException('Your current step does not allow that.');
        }
    }
}
