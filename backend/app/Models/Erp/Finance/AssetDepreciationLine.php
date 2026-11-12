<?php

namespace App\Models\Erp\Finance;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AssetDepreciationLine extends Model
{
    use BelongsToTenant;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'asset_depreciation_run_id' => 'integer',
            'fixed_asset_id' => 'integer',
            'opening_value' => 'decimal:2',
            'amount' => 'decimal:2',
            'closing_value' => 'decimal:2',
        ];
    }

    public function run(): BelongsTo
    {
        return $this->belongsTo(AssetDepreciationRun::class, 'asset_depreciation_run_id');
    }

    public function asset(): BelongsTo
    {
        return $this->belongsTo(FixedAsset::class, 'fixed_asset_id');
    }
}
