<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\VoucherResource;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherAttachment;
use App\Models\VoucherPayment;
use App\Services\AmountFormatter;
use App\Services\UsageLimits;
use App\Services\WorkflowEngine;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

/**
 * The paper trail for each payment: the acknowledgement the cashier prints for
 * the receiver to sign, and the signed copy filed back onto the voucher.
 */
class VoucherPaymentController extends Controller
{
    public function __construct(
        private readonly WorkflowEngine $engine,
        private readonly AmountFormatter $money,
        private readonly UsageLimits $limits,
    ) {}

    /** The printable acknowledgement for one payment, as a PDF. */
    public function acknowledgement(Request $request, Voucher $voucher, VoucherPayment $payment)
    {
        $this->authorizePayment($request, $voucher, $payment);

        $locale = $request->query('lang') === 'sw' ? 'sw' : ($request->user()->locale === 'sw' ? 'sw' : 'en');
        $voucher->loadMissing(['company', 'department', 'payments']);
        $payment->loadMissing('paidBy');

        $paidBefore = (float) $voucher->payments->where('sequence', '<', $payment->sequence)->sum('amount');
        $currency = $voucher->currency ?: 'TZS';
        $logo = $voucher->company?->logo_path ? Storage::disk('public')->path($voucher->company->logo_path) : null;

        $pdf = Pdf::loadView('pdf.payment-acknowledgement', [
            'voucher' => $voucher,
            'payment' => $payment,
            'company' => $voucher->company,
            'locale' => $locale,
            'fmt' => fn ($v) => $this->money->money((float) $v, $currency),
            'amountWords' => $this->money->inWords((float) $payment->amount, $currency),
            'paidBefore' => $paidBefore,
            'balanceAfter' => (float) $payment->balance_after,
            'partsTotal' => $voucher->payments->count(),
            'cashierSignature' => $payment->paidBy?->signature_data,
            'logo' => $logo && is_readable($logo) ? $logo : null,
            'timezone' => $voucher->company?->timezone ?: 'Africa/Dar_es_Salaam',
            'generatedAt' => now($voucher->company?->timezone ?: 'Africa/Dar_es_Salaam')->format('j M Y, H:i'),
        ])->setPaper('a4', 'portrait');

        $name = 'acknowledgement-'.str_replace('/', '-', $payment->reference()).'.pdf';

        return $request->boolean('download') ? $pdf->download($name) : $pdf->stream($name);
    }

    /** Files the receiver's signed acknowledgement against its payment. */
    public function storeAcknowledgement(Request $request, Voucher $voucher, VoucherPayment $payment)
    {
        $this->authorizePayment($request, $voucher, $payment);
        $user = $request->user();

        abort_unless($this->mayFile($user, $voucher, $payment), 403, 'Only the cashier who paid, or a company admin, can file the signed acknowledgement.');

        $maxKb = (int) config('vouchflow.max_upload_mb', 10) * 1024;
        $request->validate([
            'file' => ['required', 'file', "max:{$maxKb}", 'mimetypes:'.implode(',', config('vouchflow.allowed_upload_mimes'))],
        ], [
            'file.mimetypes' => 'The signed acknowledgement must be a PDF or an image.',
            'file.max' => "The file must be under {$maxKb} KB.",
        ]);

        $file = $request->file('file');
        $this->limits->assertUploadSize($file->getSize());

        $extension = $file->getClientOriginalExtension() ?: 'pdf';
        $document = VoucherAttachment::create([
            'voucher_id' => $voucher->id,
            'voucher_payment_id' => $payment->id,
            'company_id' => $voucher->company_id,
            'uploaded_by' => $user->id,
            'original_name' => 'Signed acknowledgement '.str_replace('/', '-', $payment->reference()).'.'.$extension,
            'path' => $file->store("companies/{$voucher->company_id}/vouchers/{$voucher->id}", 'local'),
            'disk' => 'local',
            'mime_type' => $file->getClientMimeType(),
            'document_type' => VoucherAttachment::TYPE_ACKNOWLEDGEMENT,
            'size_bytes' => $file->getSize(),
        ]);

        $this->engine->acknowledgePayment($payment, $user, $document);

        $fresh = $voucher->fresh()->load([
            'requester', 'department', 'voucherType', 'paidBy', 'workflow.steps',
            'approvals.actor', 'attachments.uploader', 'comments.user', 'payments.paidBy', 'payments.acknowledgements',
        ])->loadCount(['attachments', 'comments']);

        return (new VoucherResource($fresh))->detailed()->response()->setStatusCode(201);
    }

    private function mayFile(User $user, Voucher $voucher, VoucherPayment $payment): bool
    {
        return $user->isCompanyAdmin()
            || $payment->paid_by_id === $user->id
            || $this->engine->canPay($user, $voucher);
    }

    private function authorizePayment(Request $request, Voucher $voucher, VoucherPayment $payment): void
    {
        if (Gate::forUser($request->user())->denies('view', $voucher)) {
            throw new AccessDeniedHttpException('This voucher belongs to another part of the business.');
        }

        abort_unless($payment->voucher_id === $voucher->id, 404);
    }
}
