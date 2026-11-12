<?php

namespace App\Http\Controllers\Api\Erp\Hr;

use App\Http\Controllers\Controller;
use App\Http\Resources\Erp\Hr\EmployeeResource;
use App\Models\Erp\Hr\Applicant;
use App\Models\Erp\Hr\Contract;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\Vacancy;
use App\Services\AuditLogger;
use App\Services\Erp\Hr\EmployeeService;
use App\Services\Erp\Hr\HrAccess;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/** Vacancies, applicants moving through stages, and hiring into an employee record. */
class RecruitmentController extends Controller
{
    public function __construct(private readonly AuditLogger $audit, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(Vacancy::query()->with('department:id,name')->withCount('applicants')
            ->withCount(['applicants as hired_count' => fn ($q) => $q->where('stage', 'hired')])
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->latest('id')->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(Vacancy $vacancy): JsonResponse
    {
        return response()->json(['data' => $vacancy->load('department:id,name', 'applicants.employee:id,full_name,employee_number')]);
    }

    public function store(Request $request): JsonResponse
    {
        $vacancy = Vacancy::create([...$this->vacancyData($request), 'created_by' => $request->user()->id]);
        $this->audit->log('hr.vacancy.created', "Opened vacancy {$vacancy->title}", $vacancy);

        return response()->json(['message' => 'Vacancy saved.', 'data' => $vacancy], 201);
    }

    public function update(Request $request, Vacancy $vacancy): JsonResponse
    {
        $vacancy->update($this->vacancyData($request, true));
        $this->audit->log('hr.vacancy.updated', "Updated vacancy {$vacancy->title}", $vacancy);

        return response()->json(['message' => 'Vacancy saved.', 'data' => $vacancy]);
    }

    public function storeApplicant(Request $request, Vacancy $vacancy): JsonResponse
    {
        if ($vacancy->status !== 'open') {
            throw new RuntimeException('This vacancy is no longer open.');
        }

        $applicant = $vacancy->applicants()->create($request->validate([
            'name' => ['required', 'string', 'max:160'],
            'email' => ['nullable', 'email', 'max:160'],
            'phone' => ['nullable', 'string', 'max:40'],
            'notes' => ['nullable', 'string', 'max:1000'],
        ]) + ['stage' => 'applied']);

        return response()->json(['message' => 'Applicant added.', 'data' => $applicant], 201);
    }

    public function updateApplicant(Request $request, Applicant $applicant): JsonResponse
    {
        $data = $request->validate([
            'stage' => ['sometimes', Rule::in(array_diff(Applicant::STAGES, ['hired']))],
            'notes' => ['nullable', 'string', 'max:1000'],
            'email' => ['nullable', 'email', 'max:160'],
            'phone' => ['nullable', 'string', 'max:40'],
        ]);

        if ($applicant->stage === 'hired') {
            throw new RuntimeException("{$applicant->name} has been hired; their record is now an employee.");
        }

        $applicant->update($data);
        $this->audit->log('hr.applicant.updated', "{$applicant->name}: {$applicant->stage}", $applicant);

        return response()->json(['message' => 'Applicant saved.', 'data' => $applicant]);
    }

    public function hire(Request $request, Applicant $applicant, EmployeeService $employees): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'hire_date' => ['required', 'date'],
            'probation_end' => ['nullable', 'date', 'after:hire_date'],
            'employee_number' => ['nullable', 'string', 'max:40', Rule::unique('hr_employees', 'employee_number')->where('company_id', $company)],
            'grade' => ['nullable', 'string', 'max:20'],
            'department_id' => ['nullable', 'integer', Rule::exists('departments', 'id')->where('company_id', $company)],
            'employment_type' => ['nullable', Rule::in(Employee::EMPLOYMENT_TYPES)],
            'contract' => ['nullable', 'array'],
            'contract.type' => ['required_with:contract', Rule::in(Contract::TYPES)],
            'contract.start_date' => ['required_with:contract', 'date'],
            'contract.end_date' => ['nullable', 'date'],
            'contract.basic_salary' => ['required_with:contract', 'numeric', 'min:0'],
            'contract.housing_allowance' => ['nullable', 'numeric', 'min:0'],
            'contract.transport_allowance' => ['nullable', 'numeric', 'min:0'],
            'contract.other_allowance' => ['nullable', 'numeric', 'min:0'],
        ]);

        $contract = $data['contract'] ?? null;
        unset($data['contract']);
        abort_if($contract && ! HrAccess::seesSalary($request->user()), 403, 'Setting pay needs the salary permission.');

        $employee = $employees->hire($applicant, array_filter($data, fn ($v) => $v !== null), $contract, $request->user());

        return response()->json(['message' => "{$employee->full_name} hired.", 'data' => new EmployeeResource($employee->load('department', 'activeContract'))], 201);
    }

    /** @return array<string, mixed> */
    private function vacancyData(Request $request, bool $partial = false): array
    {
        $required = $partial ? 'sometimes' : 'required';

        return $request->validate([
            'title' => [$required, 'string', 'max:160'],
            'department_id' => ['nullable', 'integer', Rule::exists('departments', 'id')->where('company_id', $this->tenant->id())],
            'positions' => [$required, 'integer', 'between:1,500'],
            'employment_type' => [$required, Rule::in(Employee::EMPLOYMENT_TYPES)],
            'location' => ['nullable', 'string', 'max:120'],
            'description' => ['nullable', 'string', 'max:5000'],
            'closing_date' => ['nullable', 'date'],
            'status' => ['sometimes', Rule::in(Vacancy::STATUSES)],
        ]);
    }
}
