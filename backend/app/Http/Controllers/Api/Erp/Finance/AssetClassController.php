<?php

namespace App\Http\Controllers\Api\Erp\Finance;

use App\Http\Controllers\Controller;
use App\Models\Erp\Account;
use App\Models\Erp\Finance\AssetClass;
use App\Services\AuditLogger;
use App\Services\Erp\Finance\AssetClasses;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

class AssetClassController extends Controller
{
    public function __construct(private readonly TenantContext $tenant, private readonly AuditLogger $audit) {}

    public function index(AssetClasses $classes): JsonResponse
    {
        $classes->ensureDefaults();

        return response()->json(['data' => AssetClass::query()
            ->with('assetAccount:id,code,name', 'depreciationAccount:id,code,name', 'expenseAccount:id,code,name')
            ->withCount('assets')->orderBy('code')->get()]);
    }

    public function store(Request $request): JsonResponse
    {
        $class = AssetClass::create($this->rules($request));
        $this->audit->log('assets.class.created', "Added asset class {$class->code} {$class->name}", $class);

        return response()->json(['data' => $class], 201);
    }

    public function update(Request $request, AssetClass $assetClass): JsonResponse
    {
        $data = $this->rules($request, $assetClass);
        $before = $assetClass->only(['method', 'useful_life_months', 'rate']);
        $assetClass->update($data);
        // Assets already registered keep the basis they were registered on.
        $this->audit->log('assets.class.updated', "Updated asset class {$assetClass->code}", $assetClass, $before, $assetClass->only(array_keys($before)));

        return response()->json(['data' => $assetClass]);
    }

    /** Accounts an asset class may use: asset accounts for cost and depreciation, expense accounts for the charge. */
    public function accounts(): JsonResponse
    {
        return response()->json(['data' => Account::query()->whereIn('type', ['asset', 'expense'])->where('is_active', true)->orderBy('code')->get(['id', 'code', 'name', 'type'])]);
    }

    /** @return array<string, mixed> */
    private function rules(Request $request, ?AssetClass $class = null): array
    {
        $company = $this->tenant->id();
        $asset = Rule::exists('accounts', 'id')->where('company_id', $company)->where('type', 'asset');

        $data = $request->validate([
            'code' => ['required', 'string', 'max:20', Rule::unique('asset_classes')->where('company_id', $company)->ignore($class?->id)],
            'name' => ['required', 'string', 'max:120'],
            'method' => ['required', Rule::in(AssetClass::METHODS)],
            'useful_life_months' => ['required', 'integer', 'between:1,1200'],
            'rate' => ['nullable', 'numeric', 'between:0,100'],
            'asset_account_id' => ['required', 'integer', $asset],
            'depreciation_account_id' => ['required', 'integer', $asset, 'different:asset_account_id'],
            'expense_account_id' => ['required', 'integer', Rule::exists('accounts', 'id')->where('company_id', $company)->where('type', 'expense')],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        if ($data['method'] === AssetClass::METHOD_REDUCING_BALANCE && (float) ($data['rate'] ?? 0) <= 0) {
            throw new RuntimeException('Reducing balance needs an annual rate.');
        }

        return [...$data, 'rate' => $data['rate'] ?? 0];
    }
}
