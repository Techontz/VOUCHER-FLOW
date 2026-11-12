<?php

namespace App\Http\Controllers\Api\Erp\Hr;

use App\Http\Controllers\Controller;
use App\Models\Erp\Hr\Loan;
use App\Models\Erp\Hr\PayItem;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Services\Erp\Hr\HrAccess;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * Staff loans and salary advances with their repayment schedules, and the
 * extra earnings and deductions payroll picks up month by month.
 */
class LoanController extends Controller
{
    public function __construct(private readonly AuditLogger $audit, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        $this->assertReader($request);

        return response()->json(Loan::query()->with('employee:id,full_name,employee_number')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('employee_id'), fn ($q, $v) => $q->where('employee_id', $v))
            ->latest('issued_on')->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(Request $request, Loan $loan): JsonResponse
    {
        $this->assertReader($request);

        return response()->json(['data' => $loan->load('employee:id,full_name,employee_number', 'repayments'), 'schedule' => $loan->schedule()]);
    }

    public function store(Request $request, DocumentNumberer $numbers): JsonResponse
    {
        $data = $request->validate([
            'employee_id' => ['required', 'integer', Rule::exists('hr_employees', 'id')->where('company_id', $this->tenant->id())->where('status', 'active')],
            'type' => ['required', Rule::in(Loan::TYPES)],
            'principal' => ['required', 'numeric', 'min:1', 'max:999999999'],
            'installment' => ['required', 'numeric', 'min:1', 'lte:principal'],
            'start_period' => ['required', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'],
            'issued_on' => ['required', 'date', 'before_or_equal:today'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        $loan = Loan::create([
            ...$data,
            'number' => $numbers->next($data['type'] === 'advance' ? 'ADV' : 'LOAN'),
            'balance' => $data['principal'],
            'status' => Loan::STATUS_ACTIVE,
            'created_by' => $request->user()->id,
        ]);
        $this->audit->log('hr.loan.created', "Recorded {$loan->type} {$loan->number} of ".number_format((float) $loan->principal, 2), $loan);

        return response()->json(['message' => "{$loan->number} recorded.", 'data' => $loan, 'schedule' => $loan->schedule()], 201);
    }

    public function cancel(Request $request, Loan $loan): JsonResponse
    {
        if ($loan->status !== Loan::STATUS_ACTIVE) {
            throw new RuntimeException("{$loan->number} is {$loan->status}.");
        }

        if ($loan->repayments()->exists()) {
            throw new RuntimeException("{$loan->number} has repayments; it can only be settled through payroll.");
        }

        $loan->update(['status' => Loan::STATUS_CANCELLED]);
        $this->audit->log('hr.loan.cancelled', "Cancelled {$loan->number}", $loan);

        return response()->json(['message' => "{$loan->number} cancelled.", 'data' => $loan]);
    }

    public function items(Request $request): JsonResponse
    {
        $this->assertReader($request);

        return response()->json(PayItem::query()->with('employee:id,full_name,employee_number')
            ->when($request->has('active'), fn ($q) => $q->where('is_active', $request->boolean('active')))
            ->when($request->query('employee_id'), fn ($q, $v) => $q->where('employee_id', $v))
            ->latest('id')->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function storeItem(Request $request): JsonResponse
    {
        $item = PayItem::create([...$this->itemData($request), 'created_by' => $request->user()->id]);
        $this->audit->log('hr.pay_item.created', "Added {$item->kind} '{$item->description}' of ".number_format((float) $item->amount, 2), $item);

        return response()->json(['message' => 'Pay item saved.', 'data' => $item], 201);
    }

    public function updateItem(Request $request, PayItem $payItem): JsonResponse
    {
        $payItem->update($this->itemData($request));
        $this->audit->log('hr.pay_item.updated', "Updated {$payItem->kind} '{$payItem->description}'", $payItem);

        return response()->json(['message' => 'Pay item saved.', 'data' => $payItem]);
    }

    /** @return array<string, mixed> */
    private function itemData(Request $request): array
    {
        $data = $request->validate([
            'employee_id' => ['required', 'integer', Rule::exists('hr_employees', 'id')->where('company_id', $this->tenant->id())],
            'kind' => ['required', Rule::in(PayItem::KINDS)],
            'category' => ['required', Rule::in(PayItem::CATEGORIES)],
            'description' => ['required', 'string', 'max:160'],
            'amount' => ['required', 'numeric', 'min:0.01', 'max:999999999'],
            'start_period' => ['required', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'],
            'end_period' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        if (! empty($data['end_period']) && $data['end_period'] < $data['start_period']) {
            throw new RuntimeException('The last month cannot be before the first.');
        }

        return $data;
    }

    private function assertReader(Request $request): void
    {
        abort_unless(HrAccess::worksOnPayroll($request->user()) || HrAccess::seesSalary($request->user()), 403, 'Your role does not allow you to see loans and pay items.');
    }
}
