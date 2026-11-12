<?php

namespace App\Http\Controllers\Api\Erp\Hr;

use App\Http\Controllers\Controller;
use App\Models\Company;
use App\Models\Erp\Account;
use App\Models\Erp\Hr\PayrollRun;
use App\Models\Erp\Hr\Payslip;
use App\Models\Erp\Hr\StatutoryRate;
use App\Services\AuditLogger;
use App\Services\Erp\Hr\HrAccess;
use App\Services\Erp\Hr\PayrollService;
use App\Services\Erp\Hr\StatutoryRates;
use App\Support\TenantContext;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Validation\Rule;

/**
 * Payroll runs from preparation to payment, payslips, the statutory returns
 * summary and the statutory rates themselves.
 *
 * Reading payroll needs one of the payroll permissions; each step needs its
 * own (prepare, authorise, post), checked by the route.
 */
class PayrollController extends Controller
{
    public function __construct(
        private readonly PayrollService $payroll,
        private readonly StatutoryRates $rates,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $this->assertPayroll($request);

        return response()->json(PayrollRun::query()->with('preparer:id,name', 'authoriser:id,name')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('year'), fn ($q, $v) => $q->where('period', 'like', "{$v}-%"))
            ->orderByDesc('period')
            ->paginate(min((int) $request->query('per_page', 24), 100)));
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'period' => ['required', 'string', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'],
            'notes' => ['nullable', 'string', 'max:500'],
        ]);
        ['run' => $run, 'skipped' => $skipped] = $this->payroll->prepare($data['period'], $request->user(), $data['notes'] ?? null);

        return response()->json(['message' => "{$run->number} prepared.", 'data' => $run, 'skipped' => $skipped], 201);
    }

    public function show(Request $request, PayrollRun $payrollRun): JsonResponse
    {
        $this->assertPayroll($request);
        $user = $request->user();
        $payrollRun->load('preparer:id,name', 'authoriser:id,name', 'locker:id,name', 'poster:id,name', 'payer:id,name',
            'journal:id,number,status,total', 'paymentJournal:id,number,status,total', 'paymentAccount:id,code,name');

        return response()->json([
            'data' => $payrollRun,
            'payslips' => $payrollRun->payslips()->orderBy('employee_name')->get(),
            'posting' => $this->payroll->postingLines($payrollRun),
            'can' => [
                'recalculate' => $payrollRun->status === PayrollRun::STATUS_DRAFT && $user->hasPermission('hr.payroll.prepare'),
                'authorise' => $payrollRun->status === PayrollRun::STATUS_DRAFT && $user->hasPermission('hr.payroll.authorise') && $payrollRun->prepared_by !== $user->id,
                'return' => $payrollRun->status === PayrollRun::STATUS_AUTHORISED && $user->hasPermission('hr.payroll.authorise'),
                'lock' => $payrollRun->status === PayrollRun::STATUS_AUTHORISED && $user->hasPermission('hr.payroll.authorise'),
                'post' => $payrollRun->status === PayrollRun::STATUS_LOCKED && $user->hasPermission('hr.payroll.post'),
                'pay' => $payrollRun->status === PayrollRun::STATUS_POSTED && $user->hasPermission('hr.payroll.post'),
                'delete' => $payrollRun->status === PayrollRun::STATUS_DRAFT && $user->hasPermission('hr.payroll.prepare'),
            ],
        ]);
    }

    public function recalculate(Request $request, PayrollRun $payrollRun): JsonResponse
    {
        ['run' => $run, 'skipped' => $skipped] = $this->payroll->recalculate($payrollRun, $request->user());

        return response()->json(['message' => "{$run->number} recalculated.", 'data' => $run, 'skipped' => $skipped]);
    }

    public function authorise(Request $request, PayrollRun $payrollRun): JsonResponse
    {
        $run = $this->payroll->authorise($payrollRun, $request->user());

        return response()->json(['message' => "{$run->number} authorised.", 'data' => $run]);
    }

    public function returnToDraft(Request $request, PayrollRun $payrollRun): JsonResponse
    {
        $reason = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:255']])['reason'];
        $run = $this->payroll->returnToDraft($payrollRun, $request->user(), $reason);

        return response()->json(['message' => "{$run->number} returned to draft.", 'data' => $run]);
    }

    public function lock(Request $request, PayrollRun $payrollRun): JsonResponse
    {
        $run = $this->payroll->lockRun($payrollRun, $request->user());

        return response()->json(['message' => "{$run->number} locked.", 'data' => $run]);
    }

    public function post(Request $request, PayrollRun $payrollRun): JsonResponse
    {
        $run = $this->payroll->post($payrollRun, $request->user());

        return response()->json(['message' => "{$run->number} posted.", 'data' => $run]);
    }

    public function pay(Request $request, PayrollRun $payrollRun): JsonResponse
    {
        $data = $request->validate([
            'account_id' => ['required', 'integer', Rule::exists('accounts', 'id')->where('company_id', $this->tenant->id())],
            'payment_date' => ['nullable', 'date', 'before_or_equal:today'],
        ]);
        $run = $this->payroll->pay($payrollRun, (int) $data['account_id'], $data['payment_date'] ?? null, $request->user());

        return response()->json(['message' => "Net salaries of {$run->number} recorded as paid.", 'data' => $run]);
    }

    public function destroy(Request $request, PayrollRun $payrollRun): JsonResponse
    {
        $this->payroll->delete($payrollRun, $request->user());

        return response()->json(['message' => 'Draft deleted.']);
    }

    /** Cash and bank accounts salaries can be paid from. */
    public function paymentAccounts(Request $request): JsonResponse
    {
        $this->assertPayroll($request);

        return response()->json(['data' => Account::query()->where('type', 'asset')->where('is_active', true)
            ->whereBetween('code', ['1100', '1299'])->orderBy('code')->get(['id', 'code', 'name'])]);
    }

    public function payslip(Request $request, Payslip $payslip): JsonResponse
    {
        $this->assertPayroll($request);

        return response()->json(['data' => $this->presentPayslip($payslip)]);
    }

    public function payslipPdf(Request $request, Payslip $payslip): Response
    {
        $this->assertPayroll($request);

        return $this->pdf($payslip);
    }

    /**
     * Statutory totals per month for a year, from runs that are locked or
     * later (what will be, or has been, declared).
     */
    public function statutory(Request $request): JsonResponse
    {
        $this->assertPayroll($request);
        $year = (int) $request->query('year', now()->year);

        $runs = PayrollRun::query()
            ->whereIn('status', [PayrollRun::STATUS_LOCKED, PayrollRun::STATUS_POSTED, PayrollRun::STATUS_PAID])
            ->where('period', 'like', "{$year}-%")->orderBy('period')->get();

        $rows = $runs->map(fn (PayrollRun $r) => [
            'run_id' => $r->id, 'number' => $r->number, 'period' => $r->period, 'status' => $r->status,
            'employees' => $r->employees_count, 'gross' => (float) $r->gross,
            'paye' => (float) $r->paye, 'nssf_employee' => (float) $r->nssf_employee, 'nssf_employer' => (float) $r->nssf_employer,
            'nssf_total' => round((float) $r->nssf_employee + (float) $r->nssf_employer, 2),
            'wcf' => (float) $r->wcf, 'sdl' => (float) $r->sdl, 'heslb' => (float) $r->heslb,
        ])->values();

        $sum = fn (string $k) => round($rows->sum($k), 2);

        return response()->json([
            'year' => $year,
            'data' => $rows,
            'totals' => collect(['gross', 'paye', 'nssf_employee', 'nssf_employer', 'nssf_total', 'wcf', 'sdl', 'heslb'])->mapWithKeys(fn ($k) => [$k => $sum($k)]),
        ]);
    }

    public function rates(Request $request): JsonResponse
    {
        $this->assertPayroll($request);
        $this->rates->ensureDefaults();

        return response()->json([
            'data' => StatutoryRate::query()->orderBy('code')->orderByDesc('effective_from')->get(),
            'in_force' => array_map(StatutoryRates::describe(...), $this->rates->inForce(today())),
        ]);
    }

    /** A new version of a rule, from a date; earlier months keep the version they were paid on. */
    public function storeRate(Request $request, AuditLogger $audit): JsonResponse
    {
        $data = $request->validate([
            'code' => ['required', Rule::in(StatutoryRates::CODES)],
            'name' => ['required', 'string', 'max:120'],
            'kind' => ['required', Rule::in([StatutoryRate::KIND_PERCENT, StatutoryRate::KIND_BANDS])],
            'base' => ['required', Rule::in(['gross', 'basic', 'taxable'])],
            'party' => ['required', Rule::in(['employee', 'employer'])],
            'rate' => ['required_if:kind,percent', 'nullable', 'numeric', 'between:0,100'],
            'bands' => ['required_if:kind,bands', 'nullable', 'array', 'min:1'],
            'bands.*.from' => ['required', 'numeric', 'min:0'],
            'bands.*.to' => ['nullable', 'numeric', 'gt:bands.*.from'],
            'bands.*.base' => ['required', 'numeric', 'min:0'],
            'bands.*.rate' => ['required', 'numeric', 'between:0,100'],
            'effective_from' => ['required', 'date'],
            'country' => ['nullable', 'string', 'size:2'],
        ]);

        $this->rates->ensureDefaults($data['country'] ?? 'TZ');
        $rate = StatutoryRate::query()->updateOrCreate(
            ['country' => $data['country'] ?? 'TZ', 'code' => $data['code'], 'effective_from' => $data['effective_from']],
            [...$data, 'country' => $data['country'] ?? 'TZ', 'bands' => $data['kind'] === 'bands' ? array_values($data['bands']) : null,
                'rate' => $data['kind'] === 'percent' ? $data['rate'] : null, 'created_by' => $request->user()->id],
        );
        $audit->log('hr.statutory.updated', "Statutory rate {$rate->code} from {$rate->effective_from->toDateString()}", $rate);

        return response()->json(['message' => 'Rate saved.', 'data' => $rate], 201);
    }

    /** @return array<string, mixed> */
    public static function presentPayslip(Payslip $payslip): array
    {
        $payslip->loadMissing('run');

        return [
            ...$payslip->toArray(),
            'run' => $payslip->run->only(['id', 'number', 'period', 'period_start', 'period_end', 'status', 'payment_date']),
        ];
    }

    public static function pdf(Payslip $payslip): Response
    {
        $payslip->loadMissing('run', 'employee');
        $company = Company::query()->find($payslip->company_id);

        return Pdf::loadView('pdf.hr-payslip', ['slip' => $payslip, 'run' => $payslip->run, 'company' => $company])
            ->setPaper('a4')
            ->download("payslip-{$payslip->employee_number}-{$payslip->run->period}.pdf");
    }

    private function assertPayroll(Request $request): void
    {
        abort_unless(HrAccess::worksOnPayroll($request->user()), 403, 'Your role does not allow you to see payroll.');
    }
}
