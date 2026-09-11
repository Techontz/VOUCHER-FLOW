<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\VoucherResource;
use App\Models\Voucher;
use App\Models\VoucherType;
use App\Services\AmountFormatter;
use App\Services\AuditLogger;
use App\Services\VoucherNumberGenerator;
use App\Services\VoucherVisibility;
use App\Services\WorkflowEngine;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

class VoucherController extends Controller
{
    public function __construct(
        private readonly WorkflowEngine $engine,
        private readonly VoucherVisibility $visibility,
        private readonly VoucherNumberGenerator $numbers,
        private readonly AmountFormatter $money,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request)
    {
        $request->validate([
            'status' => ['nullable', 'string'],
            'department_id' => ['nullable', 'integer'],
            'voucher_type_id' => ['nullable', 'integer'],
            'requester_id' => ['nullable', 'integer'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
            'min_amount' => ['nullable', 'numeric'],
            'max_amount' => ['nullable', 'numeric'],
            'q' => ['nullable', 'string', 'max:120'],
            'sort' => ['nullable', Rule::in(['date', 'amount', 'number', 'status'])],
            'direction' => ['nullable', Rule::in(['asc', 'desc'])],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
            'scope' => ['nullable', Rule::in(['all', 'mine', 'pending'])],
        ]);

        $query = $this->baseQuery($request);

        $vouchers = $query
            ->orderBy($this->sortColumn($request->query('sort')), $request->query('direction', 'desc'))
            ->paginate((int) $request->query('per_page', 20))
            ->withQueryString();

        return VoucherResource::collection($vouchers)->additional([
            'meta' => [
                'total_amount' => (float) (clone $query)->sum('amount'),
                'currency' => $this->tenant->company()?->currency ?? 'TZS',
            ],
        ]);
    }

    /** The "awaiting you" queue — only steps this user may actually act on. */
    public function pending(Request $request)
    {
        $user = $request->user();

        $query = Voucher::query()
            ->with(['requester', 'department', 'voucherType', 'workflow.steps'])
            ->withCount('attachments');

        $this->visibility->pendingFor($query, $user);

        $vouchers = $this->visibility->actionableOnly(
            $query->orderBy('submitted_at')->get(),
            $user,
        );

        return VoucherResource::collection($vouchers);
    }

    public function show(Request $request, Voucher $voucher)
    {
        $this->authorizeView($request, $voucher);

        $voucher->load([
            'requester.department', 'department.hod', 'department.manager', 'voucherType',
            'workflow.steps.assignedUser', 'approvals.actor', 'attachments.uploader', 'comments.user.department',
        ])->loadCount(['attachments', 'comments']);

        return (new VoucherResource($voucher))->detailed()->response();
    }

    public function store(Request $request)
    {
        $data = $this->validateVoucher($request);
        $user = $request->user();
        $company = $this->tenant->company();

        abort_unless($company, 403, 'No company context.');

        app(\App\Services\UsageLimits::class)->assertCanCreateVoucher($company);

        $type = VoucherType::findOrFail($data['voucher_type_id']);
        $workflow = $this->engine->resolveWorkflow($type);

        $voucher = DB::transaction(function () use ($data, $user, $type, $workflow, $company) {
            $voucher = Voucher::create([
                'company_id' => $company->id,
                'number' => $this->numbers->next($type),
                'voucher_type_id' => $type->id,
                'workflow_id' => $workflow?->id,
                'department_id' => $data['department_id'] ?? $user->department_id,
                'requester_id' => $user->id,
                'payee' => $data['payee'],
                'purpose' => $data['purpose'],
                'description' => $data['description'] ?? null,
                'amount' => $data['amount'],
                'currency' => $data['currency'] ?? $company->currency,
                'amount_in_words' => $this->money->inWords((float) $data['amount'], $data['currency'] ?? $company->currency),
                'payment_method' => $data['payment_method'] ?? null,
                'account_ref' => $data['account_ref'] ?? null,
                'kind' => $data['kind'] ?? Voucher::KIND_BANK,
                'payee_bank' => $data['payee_bank'] ?? null,
                'payee_account_name' => $data['payee_account_name'] ?? null,
                'payee_account_number' => $data['payee_account_number'] ?? null,
                'payee_bank_branch' => $data['payee_bank_branch'] ?? null,
                'cash_float' => $data['cash_float'] ?? null,
                'category' => $data['category'] ?? null,
                'cost_centre' => $data['cost_centre'] ?? null,
                'voucher_date' => $data['voucher_date'] ?? now()->toDateString(),
                'notes_to_approver' => $data['notes_to_approver'] ?? null,
                'status' => Voucher::STATUS_DRAFT,
                'verification_code' => $this->numbers->verificationCode(),
                'created_by' => $user->id,
                'updated_by' => $user->id,
            ]);

            $this->engine->record($voucher, $user, 'created');

            return $voucher;
        });

        $this->audit->log('voucher.created', "Created voucher {$voucher->number}", $voucher);

        if ($request->boolean('submit')) {
            $voucher = $this->engine->submit($voucher, $user);
        }

        return $this->respond($request, $voucher, 201);
    }

    public function update(Request $request, Voucher $voucher)
    {
        $this->authorizeView($request, $voucher);
        $user = $request->user();

        abort_unless(
            $this->engine->availableActions($user, $voucher)['edit'],
            403,
            'This voucher can no longer be edited.',
        );

        $data = $this->validateVoucher($request, partial: true);
        $before = $voucher->only(['payee', 'purpose', 'amount', 'description', 'payment_method']);

        if (array_key_exists('amount', $data) || array_key_exists('currency', $data)) {
            $amount = (float) ($data['amount'] ?? $voucher->amount);
            $currency = $data['currency'] ?? $voucher->currency;
            $data['amount_in_words'] = $this->money->inWords($amount, $currency);
        }

        $voucher->fill($data + ['updated_by' => $user->id])->save();

        $this->audit->log(
            'voucher.updated',
            "Updated voucher {$voucher->number}",
            $voucher,
            $before,
            $voucher->only(['payee', 'purpose', 'amount', 'description', 'payment_method']),
        );

        return $this->respond($request, $voucher->fresh());
    }

    public function destroy(Request $request, Voucher $voucher)
    {
        $this->authorizeView($request, $voucher);

        abort_unless(
            $this->engine->availableActions($request->user(), $voucher)['delete'],
            403,
            'Only a draft may be deleted.',
        );

        $number = $voucher->number;
        $voucher->delete();

        $this->audit->log('voucher.deleted', "Deleted draft voucher {$number}", $voucher);

        return response()->json(['message' => "Draft {$number} deleted."]);
    }

    /* ------------------------------------------------------------- transitions */

    public function submit(Request $request, Voucher $voucher)
    {
        $this->authorizeView($request, $voucher);
        $data = $request->validate(['comment' => ['nullable', 'string', 'max:2000']]);

        return $this->respond($request, $this->engine->submit($voucher, $request->user(), $data['comment'] ?? null));
    }

    public function sign(Request $request, Voucher $voucher)
    {
        $this->authorizeView($request, $voucher);

        $data = $request->validate([
            'signature' => ['nullable', 'string', 'max:1500000'],
            'comment' => ['nullable', 'string', 'max:2000'],
            'use_saved_signature' => ['nullable', 'boolean'],
            'save_signature' => ['nullable', 'boolean'],
        ]);

        $user = $request->user();
        $signature = ($data['use_saved_signature'] ?? false) ? $user->signature_data : ($data['signature'] ?? null);

        if (($data['save_signature'] ?? false) && ! empty($data['signature'])) {
            $user->forceFill([
                'signature_data' => $data['signature'],
                'signature_updated_at' => now(),
            ])->save();
        }

        return $this->respond($request, $this->engine->sign($voucher, $user, $signature, $data['comment'] ?? null));
    }

    /** A signing-only step hands the signed voucher to the next step. */
    public function submitSigned(Request $request, Voucher $voucher)
    {
        $this->authorizeView($request, $voucher);
        $data = $request->validate(['comment' => ['nullable', 'string', 'max:2000']]);

        return $this->respond($request, $this->engine->submitSigned($voucher, $request->user(), $data['comment'] ?? null));
    }

    public function approve(Request $request, Voucher $voucher)
    {
        $this->authorizeView($request, $voucher);

        $data = $request->validate([
            'comment' => ['nullable', 'string', 'max:2000'],
            'signature' => ['nullable', 'string', 'max:1500000'],
        ]);

        return $this->respond($request, $this->engine->approve(
            $voucher, $request->user(), $data['comment'] ?? null, $data['signature'] ?? null,
        ));
    }

    /**
     * Records the release of money against an approved voucher.
     *
     * What is asked for depends on the instrument: a bank voucher needs the
     * reference the transfer can be reconciled against, a cash voucher needs the
     * name of whoever actually took the notes.
     */
    public function pay(Request $request, Voucher $voucher)
    {
        $this->authorizeView($request, $voucher);

        $data = $request->validate([
            'payment_reference' => [$voucher->isBank() ? 'required' : 'nullable', 'string', 'max:120'],
            'payment_date' => ['nullable', 'date'],
            'payment_method' => ['nullable', 'string', 'max:80'],
            'cheque_number' => ['nullable', 'string', 'max:64'],
            'received_by' => [$voucher->isBank() ? 'nullable' : 'required', 'string', 'max:120'],
            'note' => ['nullable', 'string', 'max:2000'],
            'signature' => ['nullable', 'string', 'max:1500000'],
        ]);

        return $this->respond($request, $this->engine->pay(
            $voucher, $request->user(), $data, $data['signature'] ?? null,
        ));
    }

    /** Approved and unpaid, for whoever the workflow entrusts with the money. */
    public function awaitingPayment(Request $request)
    {
        $user = $request->user();

        $query = Voucher::query()
            ->with(['requester', 'department', 'voucherType', 'workflow.steps'])
            ->withCount('attachments')
            ->awaitingPayment()
            ->kind($request->query('kind'));

        $this->visibility->apply($query, $user);

        $vouchers = $query->orderBy('approved_at')->get()
            ->filter(fn (Voucher $v) => $this->engine->canPay($user, $v))
            ->values();

        return VoucherResource::collection($vouchers);
    }

    public function reject(Request $request, Voucher $voucher)
    {
        $this->authorizeView($request, $voucher);
        $data = $request->validate(['comment' => ['required', 'string', 'max:2000']]);

        return $this->respond($request, $this->engine->reject($voucher, $request->user(), $data['comment']));
    }

    public function requestChanges(Request $request, Voucher $voucher)
    {
        $this->authorizeView($request, $voucher);
        $data = $request->validate(['comment' => ['required', 'string', 'max:2000']]);

        return $this->respond($request, $this->engine->requestChanges($voucher, $request->user(), $data['comment']));
    }

    public function cancel(Request $request, Voucher $voucher)
    {
        $this->authorizeView($request, $voucher);
        $data = $request->validate(['comment' => ['nullable', 'string', 'max:2000']]);

        return $this->respond($request, $this->engine->cancel($voucher, $request->user(), $data['comment'] ?? null));
    }

    /* ---------------------------------------------------------------- helpers */

    /**
     * Every read of a single voucher passes through here. Tenant isolation is
     * already guaranteed by the global scope; this adds the row-level rule that an
     * employee sees only their own record.
     */
    private function authorizeView(Request $request, Voucher $voucher): void
    {
        $visible = $this->visibility
            ->apply(Voucher::query()->whereKey($voucher->id), $request->user())
            ->exists();

        if (! $visible) {
            throw new AccessDeniedHttpException('This voucher belongs to another part of the business.');
        }
    }

    private function baseQuery(Request $request)
    {
        $user = $request->user();

        $query = Voucher::query()
            ->with(['requester', 'department', 'voucherType', 'workflow.steps'])
            ->withCount(['attachments', 'comments']);

        $scope = $request->query('scope', 'all');

        if ($scope === 'pending') {
            $this->visibility->pendingFor($query, $user);
        } else {
            $this->visibility->apply($query, $user);
        }

        if ($scope === 'mine') {
            $query->where('vouchers.requester_id', $user->id);
        }

        return $query
            ->status($request->query('status'))
            ->search($request->query('q'))
            ->when($request->query('department_id'), fn ($q, $v) => $q->where('vouchers.department_id', $v))
            ->when($request->query('voucher_type_id'), fn ($q, $v) => $q->where('vouchers.voucher_type_id', $v))
            ->when($request->query('requester_id'), fn ($q, $v) => $q->where('vouchers.requester_id', $v))
            ->when($request->query('from'), fn ($q, $v) => $q->whereDate('vouchers.voucher_date', '>=', $v))
            ->when($request->query('to'), fn ($q, $v) => $q->whereDate('vouchers.voucher_date', '<=', $v))
            ->when($request->query('min_amount'), fn ($q, $v) => $q->where('vouchers.amount', '>=', $v))
            ->when($request->query('max_amount'), fn ($q, $v) => $q->where('vouchers.amount', '<=', $v));
    }

    private function sortColumn(?string $sort): string
    {
        return match ($sort) {
            'amount' => 'vouchers.amount',
            'number' => 'vouchers.number',
            'status' => 'vouchers.status',
            default => 'vouchers.voucher_date',
        };
    }

    private function validateVoucher(Request $request, bool $partial = false): array
    {
        $required = $partial ? 'sometimes' : 'required';

        return $request->validate([
            'voucher_type_id' => [$partial ? 'sometimes' : 'required', 'integer', Rule::exists('voucher_types', 'id')],
            'department_id' => ['nullable', 'integer', Rule::exists('departments', 'id')],
            'payee' => [$required, 'string', 'max:180'],
            'purpose' => [$required, 'string', 'max:255'],
            'description' => ['nullable', 'string', 'max:5000'],
            'amount' => [$required, 'numeric', 'min:0.01', 'max:999999999999'],
            'currency' => ['nullable', 'string', 'size:3'],
            'payment_method' => ['nullable', 'string', 'max:60'],
            'account_ref' => ['nullable', 'string', 'max:120'],

            // Which instrument this is, and the particulars that belong to it.
            // Bank fields are accepted only on a bank voucher and vice versa, so
            // a cash claim cannot quietly carry a branch name it will never use.
            'kind' => ['nullable', Rule::in(Voucher::KINDS)],
            'payee_bank' => ['nullable', 'string', 'max:120', 'exclude_if:kind,cash'],
            'payee_account_name' => ['nullable', 'string', 'max:180', 'exclude_if:kind,cash'],
            'payee_account_number' => ['nullable', 'string', 'max:64', 'exclude_if:kind,cash'],
            'payee_bank_branch' => ['nullable', 'string', 'max:120', 'exclude_if:kind,cash'],
            'cash_float' => ['nullable', 'string', 'max:120', 'exclude_if:kind,bank'],

            'category' => ['nullable', 'string', 'max:120'],
            'cost_centre' => ['nullable', 'string', 'max:120'],
            'voucher_date' => ['nullable', 'date'],
            'notes_to_approver' => ['nullable', 'string', 'max:2000'],
        ]);
    }

    private function respond(Request $request, Voucher $voucher, int $status = 200)
    {
        $voucher->load([
            'requester', 'department', 'voucherType', 'workflow.steps',
            'approvals.actor', 'attachments', 'comments.user',
        ])->loadCount(['attachments', 'comments']);

        return (new VoucherResource($voucher))->detailed()->response()->setStatusCode($status);
    }
}
