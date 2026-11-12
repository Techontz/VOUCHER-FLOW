<?php

namespace App\Http\Controllers\Api\Erp\Finance;

use App\Http\Controllers\Controller;
use App\Models\Erp\Finance\AssetDepreciationRun;
use App\Services\Erp\Finance\Depreciation;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DepreciationController extends Controller
{
    public function __construct(private readonly Depreciation $depreciation) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(AssetDepreciationRun::query()->with('creator:id,name', 'journal:id,number')
            ->latest('period')->paginate(min((int) $request->query('per_page', 24), 100)));
    }

    public function show(AssetDepreciationRun $depreciationRun): JsonResponse
    {
        return response()->json(['data' => $depreciationRun->load('lines.asset:id,tag,name,asset_class_id', 'lines.asset.assetClass:id,name', 'creator:id,name', 'journal.lines.account:id,code,name')]);
    }

    public function preview(Request $request): JsonResponse
    {
        $period = $request->validate(['period' => ['required', 'string']])['period'];

        return response()->json(['data' => $this->depreciation->preview($period)]);
    }

    public function store(Request $request): JsonResponse
    {
        $period = $request->validate(['period' => ['required', 'string']])['period'];
        $run = $this->depreciation->run($period, $request->user());

        return response()->json(['message' => "Depreciation {$run->number} posted.", 'data' => $run], 201);
    }
}
