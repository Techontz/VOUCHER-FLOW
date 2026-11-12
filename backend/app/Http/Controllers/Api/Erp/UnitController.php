<?php

namespace App\Http\Controllers\Api\Erp;

use App\Http\Controllers\Controller;
use App\Models\Erp\Product;
use App\Models\Erp\Unit;
use App\Services\AuditLogger;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class UnitController extends Controller
{
    public function __construct(private readonly TenantContext $tenant, private readonly AuditLogger $audit) {}

    public function index(): JsonResponse
    {
        return response()->json(['data' => Unit::query()->orderBy('name')->get()]);
    }

    public function store(Request $request): JsonResponse
    {
        $unit = Unit::create($this->rules($request));
        $this->audit->log('unit.created', "Added unit {$unit->name}", $unit);

        return response()->json(['data' => $unit], 201);
    }

    public function update(Request $request, Unit $unit): JsonResponse
    {
        $unit->update($this->rules($request, $unit->id));
        $this->audit->log('unit.updated', "Updated unit {$unit->name}", $unit);

        return response()->json(['data' => $unit]);
    }

    public function destroy(Unit $unit): JsonResponse
    {
        abort_if(Product::withTrashed()->where('unit_id', $unit->id)->exists(), 422, "Products are measured in {$unit->name}; it cannot be deleted.");
        $unit->delete();
        $this->audit->log('unit.deleted', "Deleted unit {$unit->name}", $unit);

        return response()->json(['message' => "{$unit->name} deleted."]);
    }

    private function rules(Request $request, ?int $ignore = null): array
    {
        return $request->validate([
            'code' => ['required', 'string', 'max:20', Rule::unique('units')->where('company_id', $this->tenant->id())->ignore($ignore)],
            'name' => ['required', 'string', 'max:60'],
            'allows_decimals' => ['sometimes', 'boolean'],
        ]);
    }
}
