<?php

namespace App\Http\Controllers\Api\Erp\Hr;

use App\Http\Controllers\Controller;
use App\Models\Erp\Hr\DisciplineCase;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/** Disciplinary cases. Every route here needs hr.discipline. */
class DisciplineController extends Controller
{
    public function __construct(private readonly AuditLogger $audit, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(DisciplineCase::query()->with('employee:id,full_name,employee_number', 'opener:id,name')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('employee_id'), fn ($q, $v) => $q->where('employee_id', $v))
            ->latest('incident_date')->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(DisciplineCase $disciplineCase): JsonResponse
    {
        return response()->json(['data' => $disciplineCase->load('employee:id,full_name,employee_number,job_title', 'opener:id,name', 'closer:id,name')]);
    }

    public function store(Request $request, DocumentNumberer $numbers): JsonResponse
    {
        $data = $request->validate([
            'employee_id' => ['required', 'integer', Rule::exists('hr_employees', 'id')->where('company_id', $this->tenant->id())],
            'category' => ['required', Rule::in(DisciplineCase::CATEGORIES)],
            'incident_date' => ['required', 'date', 'before_or_equal:today'],
            'description' => ['required', 'string', 'min:5', 'max:5000'],
            'action' => ['nullable', Rule::in(DisciplineCase::ACTIONS)],
        ]);

        $case = DisciplineCase::create([...$data, 'number' => $numbers->next('DSC'), 'status' => 'open', 'opened_by' => $request->user()->id]);
        $this->audit->log('hr.discipline.opened', "Opened disciplinary case {$case->number}", $case);

        return response()->json(['message' => "{$case->number} opened.", 'data' => $case], 201);
    }

    public function update(Request $request, DisciplineCase $disciplineCase): JsonResponse
    {
        $this->assertOpen($disciplineCase);
        $disciplineCase->update($request->validate([
            'category' => ['sometimes', Rule::in(DisciplineCase::CATEGORIES)],
            'description' => ['sometimes', 'string', 'min:5', 'max:5000'],
            'action' => ['nullable', Rule::in(DisciplineCase::ACTIONS)],
            'outcome' => ['nullable', 'string', 'max:5000'],
        ]));
        $this->audit->log('hr.discipline.updated', "Updated disciplinary case {$disciplineCase->number}", $disciplineCase);

        return response()->json(['message' => 'Case saved.', 'data' => $disciplineCase]);
    }

    public function close(Request $request, DisciplineCase $disciplineCase): JsonResponse
    {
        $this->assertOpen($disciplineCase);
        $data = $request->validate([
            'action' => ['required', Rule::in(DisciplineCase::ACTIONS)],
            'outcome' => ['required', 'string', 'min:3', 'max:5000'],
        ]);

        $disciplineCase->update([...$data, 'status' => 'closed', 'closed_by' => $request->user()->id, 'closed_at' => now()]);
        $this->audit->log('hr.discipline.closed', "Closed disciplinary case {$disciplineCase->number}", $disciplineCase);

        return response()->json(['message' => "{$disciplineCase->number} closed.", 'data' => $disciplineCase]);
    }

    private function assertOpen(DisciplineCase $case): void
    {
        if ($case->status !== 'open') {
            throw new RuntimeException("{$case->number} is closed.");
        }
    }
}
