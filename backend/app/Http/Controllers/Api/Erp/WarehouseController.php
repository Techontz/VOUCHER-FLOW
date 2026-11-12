<?php

namespace App\Http\Controllers\Api\Erp;

use App\Http\Controllers\Controller;
use App\Models\Erp\StockBalance;
use App\Models\Erp\StockMovement;
use App\Models\Erp\Warehouse;
use App\Services\AuditLogger;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class WarehouseController extends Controller
{
    public const TYPES = ['warehouse', 'depot', 'shop', 'branch', 'production'];

    public function __construct(private readonly TenantContext $tenant, private readonly AuditLogger $audit) {}

    public function index(): JsonResponse
    {
        $value = StockBalance::query()
            ->selectRaw('warehouse_id, SUM(quantity * average_cost) AS v, COUNT(DISTINCT CASE WHEN quantity <> 0 THEN product_id END) AS p')
            ->groupBy('warehouse_id')->get()->keyBy('warehouse_id');

        return response()->json(['data' => Warehouse::query()->with('manager:id,name')->orderBy('name')->get()
            ->each(function (Warehouse $w) use ($value) {
                $w->setAttribute('stock_value', round((float) ($value[$w->id]->v ?? 0), 2));
                $w->setAttribute('products_held', (int) ($value[$w->id]->p ?? 0));
            })]);
    }

    public function show(Warehouse $warehouse): JsonResponse
    {
        return response()->json(['data' => $warehouse->load('manager:id,name')]);
    }

    public function store(Request $request): JsonResponse
    {
        $warehouse = Warehouse::create($this->rules($request));
        $this->audit->log('warehouse.created', "Added {$warehouse->name}", $warehouse);

        return response()->json(['data' => $warehouse], 201);
    }

    public function update(Request $request, Warehouse $warehouse): JsonResponse
    {
        $before = $warehouse->only(['name', 'type', 'is_active']);
        $warehouse->update($this->rules($request, $warehouse->id));
        $this->audit->log('warehouse.updated', "Updated {$warehouse->name}", $warehouse, $before, $warehouse->only(['name', 'type', 'is_active']));

        return response()->json(['data' => $warehouse]);
    }

    public function destroy(Warehouse $warehouse): JsonResponse
    {
        abort_if(
            StockMovement::query()->where('warehouse_id', $warehouse->id)->exists(),
            422,
            "{$warehouse->name} has stock history and cannot be deleted. Deactivate it instead.",
        );
        $warehouse->delete();
        $this->audit->log('warehouse.deleted', "Deleted {$warehouse->name}", $warehouse);

        return response()->json(['message' => "{$warehouse->name} deleted."]);
    }

    private function rules(Request $request, ?int $ignore = null): array
    {
        return $request->validate([
            'code' => ['required', 'string', 'max:20', Rule::unique('warehouses')->where('company_id', $this->tenant->id())->ignore($ignore)],
            'name' => ['required', 'string', 'max:120'],
            'type' => ['sometimes', Rule::in(self::TYPES)],
            'branch' => ['nullable', 'string', 'max:120'],
            'location' => ['nullable', 'string', 'max:255'],
            'manager_user_id' => ['nullable', 'integer', Rule::exists('users', 'id')->where('company_id', $this->tenant->id())],
            'is_active' => ['sometimes', 'boolean'],
        ]);
    }
}
