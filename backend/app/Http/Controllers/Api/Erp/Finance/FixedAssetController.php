<?php

namespace App\Http\Controllers\Api\Erp\Finance;

use App\Http\Controllers\Controller;
use App\Models\Erp\Finance\AssetDepreciationLine;
use App\Models\Erp\Finance\FixedAsset;
use App\Models\User;
use App\Services\Erp\Finance\Depreciation;
use App\Services\Erp\Finance\FixedAssets;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class FixedAssetController extends Controller
{
    public function __construct(
        private readonly FixedAssets $assets,
        private readonly Depreciation $depreciation,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(FixedAsset::query()
            ->with(['assetClass:id,code,name', 'custodian:id,name'])
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('asset_class_id'), fn ($q, $v) => $q->where('asset_class_id', $v))
            ->when($request->query('location'), fn ($q, $v) => $q->where('location', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('tag', 'like', "%{$v}%")
                ->orWhere('name', 'like', "%{$v}%")->orWhere('serial_number', 'like', "%{$v}%")))
            ->orderBy('tag')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(FixedAsset $fixedAsset): JsonResponse
    {
        $asset = $fixedAsset->load([
            'assetClass.assetAccount:id,code,name', 'assetClass.depreciationAccount:id,code,name', 'assetClass.expenseAccount:id,code,name',
            'custodian:id,name', 'supplier:id,code,name', 'fundingBankAccount:id,name', 'disposalBankAccount:id,name', 'creator:id,name',
            'events' => fn ($q) => $q->with('user:id,name', 'fromCustodian:id,name', 'toCustodian:id,name')->orderBy('event_date')->orderBy('id'),
        ]);

        return response()->json(['data' => [
            ...$asset->toArray(),
            'book_value' => $asset->bookValue(),
            'schedule' => $this->depreciation->schedule($asset),
            'depreciation' => AssetDepreciationLine::query()->where('fixed_asset_id', $asset->id)->with('run:id,number,period,journal_entry_id')->orderBy('period')->get(),
        ]]);
    }

    /** People, suppliers and places the register's forms choose from. */
    public function lookups(): JsonResponse
    {
        $company = $this->tenant->id();

        return response()->json(['data' => [
            'users' => User::query()->where('company_id', $company)->where('status', 'active')->orderBy('name')->get(['id', 'name', 'job_title']),
            'suppliers' => DB::table('suppliers')->where('company_id', $company)->whereNull('deleted_at')->orderBy('name')->get(['id', 'code', 'name']),
            'locations' => FixedAsset::query()->whereNotNull('location')->distinct()->orderBy('location')->pluck('location'),
        ]]);
    }

    public function store(Request $request): JsonResponse
    {
        return response()->json(['data' => $this->assets->register($this->rules($request), $request->user())], 201);
    }

    public function update(Request $request, FixedAsset $fixedAsset): JsonResponse
    {
        $data = $fixedAsset->status === FixedAsset::STATUS_DRAFT
            ? $this->rules($request, $fixedAsset)
            : $request->validate(['name' => ['sometimes', 'string', 'max:160'], 'description' => ['nullable', 'string', 'max:500'], 'serial_number' => ['nullable', 'string', 'max:80']]);

        return response()->json(['data' => $this->assets->update($fixedAsset, $data, $request->user())]);
    }

    public function destroy(Request $request, FixedAsset $fixedAsset): JsonResponse
    {
        $this->assets->delete($fixedAsset, $request->user());

        return response()->json(['message' => "{$fixedAsset->tag} deleted."]);
    }

    public function capitalise(Request $request, FixedAsset $fixedAsset): JsonResponse
    {
        $data = $request->validate([
            'funding' => ['required', Rule::in(FixedAssets::FUNDING)],
            'bank_account_id' => ['nullable', 'required_if:funding,bank', 'integer', Rule::exists('bank_accounts', 'id')->where('company_id', $this->tenant->id())],
        ]);
        $asset = $this->assets->capitalise($fixedAsset, $data['funding'], $data['bank_account_id'] ?? null, $request->user());

        return response()->json(['message' => "{$asset->tag} capitalised.", 'data' => $asset]);
    }

    public function transfer(Request $request, FixedAsset $fixedAsset): JsonResponse
    {
        $data = $request->validate([
            'location' => ['nullable', 'string', 'max:120'],
            'custodian_user_id' => ['nullable', 'integer', Rule::exists('users', 'id')->where('company_id', $this->tenant->id())],
            'date' => ['nullable', 'date', 'before_or_equal:today'],
            'notes' => ['nullable', 'string', 'max:500'],
        ]);
        $asset = $this->assets->transfer($fixedAsset, $data, $request->user());

        return response()->json(['message' => "{$asset->tag} moved.", 'data' => $asset]);
    }

    public function dispose(Request $request, FixedAsset $fixedAsset): JsonResponse
    {
        $data = $request->validate([
            'disposal_date' => ['required', 'date', 'before_or_equal:today'],
            'proceeds' => ['nullable', 'numeric', 'min:0', 'max:999999999999'],
            'bank_account_id' => ['nullable', 'integer', Rule::exists('bank_accounts', 'id')->where('company_id', $this->tenant->id())],
            'reason' => ['required', 'string', 'min:3', 'max:255'],
        ]);
        $asset = $this->assets->dispose($fixedAsset, $data, $request->user());

        return response()->json(['message' => "{$asset->tag} disposed of.", 'data' => $asset]);
    }

    /** @return array<string, mixed> */
    private function rules(Request $request, ?FixedAsset $asset = null): array
    {
        $company = $this->tenant->id();

        return $request->validate([
            'tag' => ['nullable', 'string', 'max:40', Rule::unique('fixed_assets')->where('company_id', $company)->ignore($asset?->id)],
            'name' => ['required', 'string', 'max:160'],
            'description' => ['nullable', 'string', 'max:500'],
            'asset_class_id' => ['required', 'integer', Rule::exists('asset_classes', 'id')->where('company_id', $company)],
            'serial_number' => ['nullable', 'string', 'max:80'],
            'location' => ['nullable', 'string', 'max:120'],
            'custodian_user_id' => ['nullable', 'integer', Rule::exists('users', 'id')->where('company_id', $company)],
            'supplier_id' => ['nullable', 'integer', Rule::exists('suppliers', 'id')->where('company_id', $company)],
            'acquisition_date' => ['required', 'date', 'before_or_equal:today'],
            'cost' => ['required', 'numeric', 'min:0.01', 'max:999999999999'],
            'residual_value' => ['nullable', 'numeric', 'min:0', 'max:999999999999'],
            'method' => ['nullable', Rule::in(['straight_line', 'reducing_balance'])],
            'useful_life_months' => ['nullable', 'integer', 'between:1,1200'],
            'rate' => ['nullable', 'numeric', 'between:0,100'],
        ]);
    }
}
