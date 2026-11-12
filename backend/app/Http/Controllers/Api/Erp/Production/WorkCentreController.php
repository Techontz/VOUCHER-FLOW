<?php

namespace App\Http\Controllers\Api\Erp\Production;

use App\Http\Controllers\Controller;
use App\Models\Erp\Production\WorkCentre;
use App\Services\AuditLogger;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Production lines and machines, with their hourly cost and capacity. */
class WorkCentreController extends Controller
{
    public function __construct(private readonly AuditLogger $audit, private readonly TenantContext $tenant) {}

    public function index(): JsonResponse
    {
        return response()->json(['data' => WorkCentre::query()->withCount('boms')->orderBy('code')->get()]);
    }

    public function store(Request $request): JsonResponse
    {
        $centre = WorkCentre::create($this->rules($request));
        $this->audit->log('production.work_centre.created', "Added work centre {$centre->code} {$centre->name}", $centre);

        return response()->json(['data' => $centre], 201);
    }

    public function update(Request $request, WorkCentre $workCentre): JsonResponse
    {
        $workCentre->update($this->rules($request, $workCentre));
        $this->audit->log('production.work_centre.updated', "Edited work centre {$workCentre->code}", $workCentre);

        return response()->json(['data' => $workCentre]);
    }

    /** @return array<string, mixed> */
    private function rules(Request $request, ?WorkCentre $centre = null): array
    {
        return $request->validate([
            'code' => ['required', 'string', 'max:20', Rule::unique('production_work_centres', 'code')
                ->where('company_id', $this->tenant->id())->ignore($centre?->id)],
            'name' => ['required', 'string', 'max:120'],
            'description' => ['nullable', 'string', 'max:2000'],
            'capacity_per_hour' => ['nullable', 'numeric', 'min:0'],
            'hourly_cost' => ['nullable', 'numeric', 'min:0'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
    }
}
