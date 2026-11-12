<?php

namespace App\Http\Controllers\Api\Erp\Hr;

use App\Http\Controllers\Controller;
use App\Models\Erp\Hr\Appraisal;
use App\Models\Erp\Hr\AppraisalObjective;
use App\Models\Erp\Hr\AppraisalPeriod;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\Training;
use App\Services\AuditLogger;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/** Appraisal periods, appraisals with weighted objectives, and training records. */
class PerformanceController extends Controller
{
    public function __construct(private readonly AuditLogger $audit, private readonly TenantContext $tenant) {}

    public function periods(): JsonResponse
    {
        return response()->json(['data' => AppraisalPeriod::query()->withCount('appraisals')->orderByDesc('start_date')->get()]);
    }

    public function storePeriod(Request $request): JsonResponse
    {
        $period = AppraisalPeriod::create($request->validate([
            'name' => ['required', 'string', 'max:120'],
            'start_date' => ['required', 'date'],
            'end_date' => ['required', 'date', 'after:start_date'],
        ]) + ['status' => 'open']);

        return response()->json(['message' => 'Appraisal period opened.', 'data' => $period], 201);
    }

    public function updatePeriod(Request $request, AppraisalPeriod $appraisalPeriod): JsonResponse
    {
        $appraisalPeriod->update($request->validate(['status' => ['required', Rule::in(['open', 'closed'])]]));

        return response()->json(['message' => 'Period saved.', 'data' => $appraisalPeriod]);
    }

    public function index(Request $request): JsonResponse
    {
        return response()->json(Appraisal::query()
            ->with('employee:id,full_name,employee_number,department_id', 'employee.department:id,name', 'period:id,name', 'reviewer:id,name')
            ->withCount('objectives')
            ->when($request->query('period_id'), fn ($q, $v) => $q->where('period_id', $v))
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('employee_id'), fn ($q, $v) => $q->where('employee_id', $v))
            ->latest('id')->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    /** Starts appraisals for the people named, or for every active employee. */
    public function store(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'period_id' => ['required', 'integer', Rule::exists('hr_appraisal_periods', 'id')->where('company_id', $company)->where('status', 'open')],
            'employee_ids' => ['nullable', 'array'],
            'employee_ids.*' => ['integer', Rule::exists('hr_employees', 'id')->where('company_id', $company)],
            'reviewer_id' => ['nullable', 'integer', Rule::exists('users', 'id')->where('company_id', $company)],
        ]);

        $ids = $data['employee_ids'] ?? Employee::query()->where('status', Employee::STATUS_ACTIVE)->pluck('id')->all();
        $created = 0;

        foreach ($ids as $id) {
            $appraisal = Appraisal::query()->firstOrCreate(
                ['period_id' => $data['period_id'], 'employee_id' => $id],
                ['reviewer_id' => $data['reviewer_id'] ?? $this->reviewerFor((int) $id), 'status' => 'draft'],
            );
            $created += $appraisal->wasRecentlyCreated ? 1 : 0;
        }

        $this->audit->log('hr.appraisal.started', "Started {$created} appraisals");

        return response()->json(['message' => "{$created} appraisals started.", 'created' => $created], 201);
    }

    public function show(Appraisal $appraisal): JsonResponse
    {
        return response()->json(['data' => $appraisal->load('employee:id,full_name,employee_number,job_title', 'period', 'reviewer:id,name', 'objectives')]);
    }

    public function update(Request $request, Appraisal $appraisal): JsonResponse
    {
        $this->assertOpen($appraisal);
        $appraisal->update($request->validate([
            'reviewer_comments' => ['nullable', 'string', 'max:5000'],
            'reviewer_id' => ['nullable', 'integer', Rule::exists('users', 'id')->where('company_id', $this->tenant->id())],
            'status' => ['sometimes', Rule::in(['draft', 'submitted'])],
        ]));

        return response()->json(['message' => 'Appraisal saved.', 'data' => $appraisal->fresh('objectives')]);
    }

    public function complete(Appraisal $appraisal): JsonResponse
    {
        $this->assertOpen($appraisal);

        if ($appraisal->objectives()->whereNull('rating')->exists() || ! $appraisal->objectives()->exists()) {
            throw new RuntimeException('Rate every objective before completing the appraisal.');
        }

        $appraisal->update(['status' => 'completed', 'overall_rating' => $appraisal->weightedRating(), 'completed_at' => now()]);
        $this->audit->log('hr.appraisal.completed', "Completed appraisal of {$appraisal->employee->full_name}: {$appraisal->overall_rating}", $appraisal);

        return response()->json(['message' => 'Appraisal completed.', 'data' => $appraisal->fresh('objectives')]);
    }

    public function storeObjective(Request $request, Appraisal $appraisal): JsonResponse
    {
        $this->assertOpen($appraisal);
        $objective = $appraisal->objectives()->create($this->objectiveData($request));

        return response()->json(['data' => $objective], 201);
    }

    public function updateObjective(Request $request, AppraisalObjective $objective): JsonResponse
    {
        $this->assertOpen(Appraisal::query()->findOrFail($objective->appraisal_id));
        $objective->update($this->objectiveData($request, true));

        return response()->json(['data' => $objective]);
    }

    public function destroyObjective(AppraisalObjective $objective): JsonResponse
    {
        $this->assertOpen(Appraisal::query()->findOrFail($objective->appraisal_id));
        $objective->delete();

        return response()->json(['message' => 'Objective removed.']);
    }

    public function trainings(Request $request): JsonResponse
    {
        return response()->json(Training::query()->with('employee:id,full_name,employee_number')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('employee_id'), fn ($q, $v) => $q->where('employee_id', $v))
            ->latest('start_date')->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function storeTraining(Request $request): JsonResponse
    {
        $training = Training::create($this->trainingData($request));
        $this->audit->log('hr.training.created', "Training '{$training->title}' recorded", $training);

        return response()->json(['message' => 'Training saved.', 'data' => $training], 201);
    }

    public function updateTraining(Request $request, Training $training): JsonResponse
    {
        $training->update($this->trainingData($request));

        return response()->json(['message' => 'Training saved.', 'data' => $training]);
    }

    private function reviewerFor(int $employeeId): ?int
    {
        $employee = Employee::query()->with('manager', 'department')->find($employeeId);

        return $employee?->manager?->user_id ?? $employee?->department?->hod_user_id;
    }

    private function assertOpen(Appraisal $appraisal): void
    {
        if ($appraisal->status === 'completed') {
            throw new RuntimeException('This appraisal is complete and cannot change.');
        }
    }

    /** @return array<string, mixed> */
    private function objectiveData(Request $request, bool $partial = false): array
    {
        return $request->validate([
            'title' => [$partial ? 'sometimes' : 'required', 'string', 'max:255'],
            'target' => ['nullable', 'string', 'max:255'],
            'weight' => ['sometimes', 'integer', 'between:1,100'],
            'rating' => ['nullable', 'integer', 'between:1,5'],
            'comment' => ['nullable', 'string', 'max:500'],
        ]);
    }

    /** @return array<string, mixed> */
    private function trainingData(Request $request): array
    {
        return $request->validate([
            'employee_id' => ['required', 'integer', Rule::exists('hr_employees', 'id')->where('company_id', $this->tenant->id())],
            'title' => ['required', 'string', 'max:160'],
            'provider' => ['nullable', 'string', 'max:160'],
            'start_date' => ['required', 'date'],
            'end_date' => ['nullable', 'date', 'after_or_equal:start_date'],
            'cost' => ['nullable', 'numeric', 'min:0'],
            'status' => ['required', Rule::in(Training::STATUSES)],
            'notes' => ['nullable', 'string', 'max:500'],
        ]);
    }
}
