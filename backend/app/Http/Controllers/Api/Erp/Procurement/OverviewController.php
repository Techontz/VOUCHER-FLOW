<?php

namespace App\Http\Controllers\Api\Erp\Procurement;

use App\Http\Controllers\Controller;
use App\Models\Department;
use App\Models\Erp\Account;
use App\Models\Erp\Procurement\ProcurementSetting;
use App\Models\Erp\Product;
use App\Models\Erp\Supplier;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\Procurement\Payables;
use App\Services\Erp\Procurement\SupplierPayments;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * The procurement overview, the reports on what is owed, the company's
 * procurement policy, and the pick-lists the procurement screens need (so a
 * person who may raise a requisition need not also hold inventory or ledger
 * permissions to fill one in).
 */
class OverviewController extends Controller
{
    public function __construct(private readonly Payables $payables) {}

    public function overview(): JsonResponse
    {
        return response()->json(['data' => $this->payables->overview()]);
    }

    public function lookups(): JsonResponse
    {
        return response()->json(['data' => [
            'departments' => Department::query()->orderBy('name')->get(['id', 'name']),
            'suppliers' => Supplier::query()->where('is_active', true)->orderBy('name')->get(['id', 'code', 'name', 'payment_terms_days']),
            'warehouses' => Warehouse::query()->where('is_active', true)->orderBy('name')->get(['id', 'code', 'name']),
            'products' => Product::query()->with('unit:id,code')->where('is_active', true)->where('type', '!=', 'service')
                ->orderBy('name')->limit(500)->get(['id', 'sku', 'name', 'unit_id', 'cost_price', 'track_batches', 'track_expiry', 'track_serials']),
            'expense_accounts' => Account::query()->where('type', 'expense')->where('is_active', true)->orderBy('code')->get(['id', 'code', 'name', 'system_key']),
            'payment_accounts' => Account::query()->where('type', 'asset')->where('is_active', true)->orderBy('code')->get(['id', 'code', 'name', 'type', 'is_active'])
                ->filter(fn ($a) => SupplierPayments::isCashOrBank($a))->values()->map->only(['id', 'code', 'name']),
            'settings' => ProcurementSetting::current(),
        ]]);
    }

    public function settings(): JsonResponse
    {
        return response()->json(['data' => ProcurementSetting::current()]);
    }

    public function updateSettings(Request $request, AuditLogger $audit): JsonResponse
    {
        $data = $request->validate([
            'approval_threshold' => ['required', 'numeric', 'min:0', 'max:999999999999'],
            'senior_roles' => ['nullable', 'array'],
            'senior_roles.*' => ['string', Rule::in(User::ASSIGNABLE_ROLES)],
            'receipt_tolerance_percent' => ['required', 'numeric', 'min:0', 'max:100'],
            'price_tolerance_percent' => ['required', 'numeric', 'min:0', 'max:100'],
            'quantity_tolerance_percent' => ['required', 'numeric', 'min:0', 'max:100'],
            'default_vat_rate' => ['required', 'numeric', 'min:0', 'max:100'],
        ]);

        $settings = ProcurementSetting::current();
        $before = $settings->only(array_keys($data));
        $settings->update($data);
        $audit->log('procurement.settings.updated', 'Changed the procurement approval and matching policy', $settings, $before, $settings->only(array_keys($data)));

        return response()->json(['data' => $settings->fresh()]);
    }

    public function ageing(Request $request): JsonResponse
    {
        $data = $request->validate(['as_of' => ['nullable', 'date']]);

        return response()->json(['data' => $this->payables->ageing($data['as_of'] ?? null)]);
    }

    public function statement(Request $request, Supplier $supplier): JsonResponse
    {
        $data = $request->validate(['from' => ['nullable', 'date'], 'to' => ['nullable', 'date', 'after_or_equal:from']]);

        return response()->json(['data' => $this->payables->statement($supplier, $data['from'] ?? null, $data['to'] ?? null)]);
    }
}
