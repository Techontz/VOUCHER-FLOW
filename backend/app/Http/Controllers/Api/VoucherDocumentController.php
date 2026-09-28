<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Department;
use App\Models\Voucher;
use App\Models\VoucherType;
use App\Services\AmountFormatter;
use App\Services\AuditLogger;
use App\Services\VoucherDocument;
use App\Services\VoucherPdfService;
use App\Services\VoucherVisibility;
use App\Services\WorkflowEngine;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

/**
 * The printed voucher. Available at every workflow stage, not only once approved,
 * subject to the step's print/download grants.
 */
class VoucherDocumentController extends Controller
{
    public function __construct(
        private readonly VoucherPdfService $pdf,
        private readonly VoucherDocument $document,
        private readonly VoucherVisibility $visibility,
        private readonly WorkflowEngine $engine,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
        private readonly AmountFormatter $money,
    ) {}

    /**
     * The document as HTML, for the on-screen voucher and the browser's print
     * dialog. Same design and same markup as the PDF.
     */
    public function html(Request $request, Voucher $voucher)
    {
        if (Gate::forUser($request->user())->denies('view', $voucher)) {
            throw new AccessDeniedHttpException('This voucher belongs to another part of the business.');
        }

        return response()->json([
            'template' => $this->document->templateFor($voucher),
            'html' => $this->document->render($voucher, app()->getLocale(), 'html'),
        ]);
    }

    /**
     * A voucher still being written, shown in the company's design before it
     * is saved. Nothing is stored: the model exists only to be rendered, so
     * the live preview goes through exactly the code the saved voucher will.
     */
    public function draftPreview(Request $request)
    {
        $user = $request->user();
        $company = $this->tenant->company();
        abort_unless($company, 403, 'No company context.');

        $data = $request->validate([
            'number' => ['nullable', 'string', 'max:40'],
            'voucher_type_id' => ['nullable', 'integer'],
            'department_id' => ['nullable', 'integer'],
            'payee' => ['nullable', 'string', 'max:180'],
            'purpose' => ['nullable', 'string', 'max:255'],
            'description' => ['nullable', 'string', 'max:5000'],
            'amount' => ['nullable', 'numeric', 'min:0', 'max:999999999999'],
            'currency' => ['nullable', 'string', 'size:3'],
            'payment_method' => ['nullable', 'string', 'max:60'],
            'account_ref' => ['nullable', 'string', 'max:120'],
            'kind' => ['nullable', Rule::in(Voucher::KINDS)],
            'payee_bank' => ['nullable', 'string', 'max:120'],
            'payee_account_name' => ['nullable', 'string', 'max:180'],
            'payee_account_number' => ['nullable', 'string', 'max:64'],
            'payee_bank_branch' => ['nullable', 'string', 'max:120'],
            'cash_float' => ['nullable', 'string', 'max:120'],
            'category' => ['nullable', 'string', 'max:120'],
            'cost_centre' => ['nullable', 'string', 'max:120'],
            'voucher_date' => ['nullable', 'date'],
            'notes_to_approver' => ['nullable', 'string', 'max:2000'],
        ]);

        // Tenant-scoped lookups: another company's type or department is simply not found.
        $type = isset($data['voucher_type_id']) ? VoucherType::find($data['voucher_type_id']) : null;
        $department = Department::find($data['department_id'] ?? $user->department_id);
        $workflow = $type ? $this->engine->resolveWorkflow($type) : null;
        $currency = $data['currency'] ?? $company->currency ?? 'TZS';
        $amount = (float) ($data['amount'] ?? 0);

        $voucher = (new Voucher)->forceFill([
            'company_id' => $company->id,
            'number' => $data['number'] ?? '—',
            'status' => Voucher::STATUS_DRAFT,
            'kind' => $data['kind'] ?? Voucher::KIND_BANK,
            'payee' => $data['payee'] ?? null,
            'purpose' => $data['purpose'] ?? null,
            'description' => $data['description'] ?? null,
            'amount' => $amount,
            'currency' => $currency,
            'amount_in_words' => $amount > 0 ? $this->money->inWords($amount, $currency) : null,
            'payment_method' => $data['payment_method'] ?? null,
            'account_ref' => $data['account_ref'] ?? null,
            'payee_bank' => $data['payee_bank'] ?? null,
            'payee_account_name' => $data['payee_account_name'] ?? null,
            'payee_account_number' => $data['payee_account_number'] ?? null,
            'payee_bank_branch' => $data['payee_bank_branch'] ?? null,
            'cash_float' => $data['cash_float'] ?? null,
            'category' => $data['category'] ?? null,
            'cost_centre' => $data['cost_centre'] ?? $department?->cost_centre,
            'voucher_date' => $data['voucher_date'] ?? now()->toDateString(),
            'notes_to_approver' => $data['notes_to_approver'] ?? null,
        ]);

        $voucher->setRelation('company', $company);
        $voucher->setRelation('requester', $user);
        $voucher->setRelation('department', $department);
        $voucher->setRelation('voucherType', $type);
        $voucher->setRelation('workflow', $workflow);
        $voucher->setRelation('paidBy', null);
        $voucher->setRelation('approvals', new EloquentCollection);
        $voucher->setRelation('attachments', new EloquentCollection);

        return response()->json([
            'template' => $this->document->templateFor($voucher),
            'html' => $this->document->render($voucher, app()->getLocale(), 'html'),
        ]);
    }

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
