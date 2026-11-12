<?php

namespace App\Http\Controllers\Api\Erp\Hr;

use App\Http\Controllers\Controller;
use App\Http\Resources\Erp\Hr\SeparationResource;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\Separation;
use App\Services\Erp\Hr\HrAccess;
use App\Services\Erp\Hr\SeparationService;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

/** Exits: notice, clearance across departments, final dues, completion. */
class SeparationController extends Controller
{
    public function __construct(private readonly SeparationService $separations, private readonly TenantContext $tenant) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        return SeparationResource::collection(Separation::query()->with('employee', 'items.clearer:id,name')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->latest('id')->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(Separation $separation): JsonResponse
    {
        return response()->json(['data' => new SeparationResource($separation->load('employee', 'items.clearer:id,name'))]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'employee_id' => ['required', 'integer', Rule::exists('hr_employees', 'id')->where('company_id', $this->tenant->id())],
            'type' => ['required', Rule::in(Separation::TYPES)],
            'notice_date' => ['required', 'date'],
            'last_working_day' => ['required', 'date'],
            'reason' => ['nullable', 'string', 'max:1000'],
            'other_dues' => ['nullable', 'numeric', 'min:0'],
        ]);
        $this->guardDues($request, $data);

        $separation = $this->separations->open(Employee::query()->findOrFail($data['employee_id']), $data, $request->user());

        return response()->json(['message' => 'Exit opened.', 'data' => new SeparationResource($separation)], 201);
    }

    public function update(Request $request, Separation $separation): JsonResponse
    {
        $data = $request->validate([
            'type' => ['sometimes', Rule::in(Separation::TYPES)],
            'last_working_day' => ['sometimes', 'date', 'after_or_equal:'.$separation->notice_date->toDateString()],
            'reason' => ['nullable', 'string', 'max:1000'],
            'other_dues' => ['nullable', 'numeric', 'min:0'],
        ]);
        $this->guardDues($request, $data);

        return response()->json(['message' => 'Exit saved.', 'data' => new SeparationResource($this->separations->update($separation, $data, $request->user()))]);
    }

    public function clear(Request $request, Separation $separation, int $item): JsonResponse
    {
        $data = $request->validate(['cleared' => ['required', 'boolean'], 'note' => ['nullable', 'string', 'max:255']]);

        return response()->json(['data' => new SeparationResource($this->separations->clear($separation, $item, $request->user(), $data['note'] ?? null, $data['cleared']))]);
    }

    public function complete(Request $request, Separation $separation): JsonResponse
    {
        return response()->json(['message' => 'Exit completed.', 'data' => new SeparationResource($this->separations->complete($separation, $request->user()))]);
    }

    /** @param  array<string, mixed>  $data */
    private function guardDues(Request $request, array $data): void
    {
        abort_if(! empty($data['other_dues']) && ! HrAccess::seesSalary($request->user()), 403, 'Final dues need the salary permission.');
    }
}
