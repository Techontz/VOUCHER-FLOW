<?php

namespace App\Http\Controllers\Api\Erp\Sales;

use App\Http\Controllers\Controller;
use App\Models\Erp\Account;
use App\Models\Erp\Customer;
use App\Models\Erp\Product;
use App\Models\Erp\Sales\PriceList;
use App\Models\Erp\Warehouse;
use App\Services\Erp\Sales\SalesPricing;
use App\Services\Erp\Sales\SalesReports;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SalesReportController extends Controller
{
    public function __construct(private readonly SalesReports $reports, private readonly SalesPricing $pricing) {}

    public function overview(): JsonResponse
    {
        return response()->json(['data' => $this->reports->overview()]);
    }

    /** Everything a sales form needs to fill its pickers, in one call. */
    public function lookups(): JsonResponse
    {
        return response()->json(['data' => [
            'customers' => Customer::query()->where('is_active', true)->orderBy('name')
                ->get(['id', 'code', 'name', 'city', 'address', 'credit_limit', 'payment_terms_days', 'requires_prepayment', 'price_list']),
            'products' => Product::query()->where('is_active', true)->with('unit:id,code,allows_decimals')->orderBy('name')
                ->get(['id', 'sku', 'name', 'type', 'unit_id', 'sale_price', 'track_batches', 'track_expiry']),
            'warehouses' => Warehouse::query()->where('is_active', true)->orderBy('name')->get(['id', 'code', 'name']),
            'price_lists' => PriceList::query()->where('is_active', true)->orderBy('name')->get(['id', 'code', 'name', 'is_default']),
            'cash_accounts' => Account::query()->where('type', 'asset')->where('is_active', true)
                ->whereRaw('CAST(code AS UNSIGNED) BETWEEN 1100 AND 1299')->orderBy('code')->get(['id', 'code', 'name']),
            'tax_rate' => $this->pricing->defaultTaxRate(),
        ]]);
    }

    public function statement(Request $request, Customer $customer): JsonResponse
    {
        $data = $request->validate(['from' => ['nullable', 'date'], 'to' => ['nullable', 'date', 'after_or_equal:from']]);

        return response()->json(['data' => $this->reports->statement(
            $customer,
            $data['from'] ?? now()->subMonths(3)->startOfMonth()->toDateString(),
            $data['to'] ?? now()->toDateString(),
        )]);
    }

    public function aged(Request $request): JsonResponse
    {
        $data = $request->validate(['as_of' => ['nullable', 'date'], 'customer_id' => ['nullable', 'integer']]);

        return response()->json(['data' => $this->reports->aged($data['as_of'] ?? now()->toDateString(), $data['customer_id'] ?? null)]);
    }

    public function sales(Request $request): JsonResponse
    {
        $data = $request->validate([
            'group' => ['nullable', 'in:customer,product,month'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date', 'after_or_equal:from'],
        ]);

        return response()->json(['data' => $this->reports->sales(
            $data['group'] ?? 'customer',
            $data['from'] ?? now()->startOfYear()->toDateString(),
            $data['to'] ?? now()->toDateString(),
        )]);
    }
}
