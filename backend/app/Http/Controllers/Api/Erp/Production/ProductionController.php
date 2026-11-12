<?php

namespace App\Http\Controllers\Api\Erp\Production;

use App\Http\Controllers\Controller;
use App\Models\Erp\Product;
use App\Models\Erp\Production\WorkCentre;
use App\Models\Erp\Warehouse;
use App\Services\Erp\Production\ProductionInsights;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** The production overview, batch genealogy and the pick lists production forms need. */
class ProductionController extends Controller
{
    public function __construct(private readonly ProductionInsights $insights) {}

    public function overview(): JsonResponse
    {
        return response()->json(['data' => $this->insights->overview()]);
    }

    public function genealogy(Request $request): JsonResponse
    {
        $data = $request->validate([
            'batch' => ['nullable', 'string', 'max:60'],
            'product_id' => ['nullable', 'integer'],
        ]);

        if (blank($data['batch'] ?? null)) {
            return response()->json(['data' => null, 'recent' => $this->insights->recentBatches()]);
        }

        return response()->json(['data' => $this->insights->genealogy(trim($data['batch']), $data['product_id'] ?? null)]);
    }

    /**
     * Products, warehouses and work centres for the production forms, so a
     * planner needs no inventory permission to fill them in.
     */
    public function options(): JsonResponse
    {
        $product = fn () => Product::query()->with('unit:id,code,name,allows_decimals')->where('is_active', true)->orderBy('name');

        return response()->json(['data' => [
            'finished' => $product()->where('type', 'finished_good')
                ->get(['id', 'sku', 'name', 'type', 'unit_id', 'cost_price', 'track_batches', 'track_expiry']),
            'materials' => $product()->where('type', '!=', 'service')
                ->get(['id', 'sku', 'name', 'type', 'unit_id', 'cost_price', 'track_batches', 'track_expiry']),
            'warehouses' => Warehouse::query()->where('is_active', true)->orderBy('name')->get(['id', 'code', 'name', 'type']),
            'work_centres' => WorkCentre::query()->where('is_active', true)->orderBy('code')->get(['id', 'code', 'name', 'hourly_cost']),
        ]]);
    }
}
