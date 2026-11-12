<?php

namespace App\Http\Controllers\Api\Erp;

use App\Http\Controllers\Controller;
use App\Models\Erp\Product;
use App\Models\Erp\StockBalance;
use App\Models\Erp\StockMovement;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Read-only views of the stock: balances, the ledger, alerts and valuation. */
class StockController extends Controller
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function balances(Request $request): JsonResponse
    {
        return response()->json(StockBalance::query()
            ->with(['product:id,sku,name,unit_id,reorder_level', 'product.unit:id,code', 'warehouse:id,code,name'])
            ->when($request->query('warehouse_id'), fn ($q, $v) => $q->where('warehouse_id', $v))
            ->when($request->query('product_id'), fn ($q, $v) => $q->where('product_id', $v))
            ->when(! $request->boolean('include_zero'), fn ($q) => $q->where('quantity', '<>', 0))
            ->when($request->query('q'), fn ($q, $v) => $q->whereHas('product', fn ($p) => $p->where('name', 'like', "%{$v}%")->orWhere('sku', 'like', "%{$v}%")))
            ->orderBy('product_id')
            ->paginate(min((int) $request->query('per_page', 50), 200))
            ->through(fn (StockBalance $b) => [
                ...$b->toArray(),
                'value' => round((float) $b->quantity * (float) $b->average_cost, 2),
            ]));
    }

    /** The inventory ledger, newest first: every movement with its source and who made it. */
    public function movements(Request $request): JsonResponse
    {
        return response()->json(StockMovement::query()
            ->with(['product:id,sku,name', 'warehouse:id,code,name', 'creator:id,name'])
            ->when($request->query('product_id'), fn ($q, $v) => $q->where('product_id', $v))
            ->when($request->query('warehouse_id'), fn ($q, $v) => $q->where('warehouse_id', $v))
            ->when($request->query('type'), fn ($q, $v) => $q->where('type', $v))
            ->when($request->query('from'), fn ($q, $v) => $q->where('movement_date', '>=', $v))
            ->when($request->query('to'), fn ($q, $v) => $q->where('movement_date', '<=', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where('reference', 'like', "%{$v}%"))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 50), 200)));
    }

    /** Products at or below their reorder level, and batches nearing expiry. */
    public function alerts(): JsonResponse
    {
        $days = (int) BusinessConfig::of($this->tenant->company())->setting('expiry_alert_days');

        $low = Product::query()->with('unit:id,code')
            ->where('is_active', true)->where('type', '!=', 'service')->where('reorder_level', '>', 0)
            ->withSum('balances as on_hand', 'quantity')
            ->get()
            ->filter(fn ($p) => (float) $p->on_hand <= (float) $p->reorder_level)
            ->values();

        $expiring = StockBalance::query()->with(['product:id,sku,name', 'warehouse:id,name'])
            ->where('quantity', '>', 0)
            ->whereNotNull('expiry_date')
            ->where('expiry_date', '<=', now()->addDays($days)->toDateString())
            ->orderBy('expiry_date')
            ->get()
            ->map(fn ($b) => [...$b->toArray(), 'expired' => $b->expiry_date->isPast()]);

        return response()->json(['data' => ['low_stock' => $low, 'expiring' => $expiring, 'expiry_window_days' => $days]]);
    }

    /** Stock value at weighted average cost, by warehouse and by category. */
    public function valuation(): JsonResponse
    {
        $byWarehouse = StockBalance::query()
            ->join('warehouses', 'warehouses.id', '=', 'stock_balances.warehouse_id')
            ->groupBy('warehouses.id', 'warehouses.name')
            ->selectRaw('warehouses.id, warehouses.name, SUM(stock_balances.quantity * stock_balances.average_cost) AS value')
            ->orderByDesc('value')->get();

        $byCategory = StockBalance::query()
            ->join('products', 'products.id', '=', 'stock_balances.product_id')
            ->leftJoin('product_categories', 'product_categories.id', '=', 'products.category_id')
            ->groupBy('product_categories.id', 'product_categories.name')
            ->selectRaw("product_categories.id, COALESCE(product_categories.name, 'Uncategorised') AS name, SUM(stock_balances.quantity * stock_balances.average_cost) AS value")
            ->orderByDesc('value')->get();

        $round = fn ($rows) => $rows->map(fn ($r) => ['id' => $r->id, 'name' => $r->name, 'value' => round((float) $r->value, 2)]);

        return response()->json(['data' => [
            'method' => 'weighted_average',
            'total' => round((float) $byWarehouse->sum('value'), 2),
            'by_warehouse' => $round($byWarehouse),
            'by_category' => $round($byCategory),
        ]]);
    }
}
