<?php

namespace App\Models\Erp\Finance;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Account;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A kind of asset: how it depreciates and which ledger accounts carry it. */
class AssetClass extends Model
{
    use BelongsToTenant;

    public const METHOD_STRAIGHT_LINE = 'straight_line';

    public const METHOD_REDUCING_BALANCE = 'reducing_balance';

    public const METHODS = [self::METHOD_STRAIGHT_LINE, self::METHOD_REDUCING_BALANCE];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'useful_life_months' => 'integer',
            'rate' => 'decimal:2',
            'asset_account_id' => 'integer',
            'depreciation_account_id' => 'integer',
            'expense_account_id' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function assetAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'asset_account_id');
    }

    public function depreciationAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'depreciation_account_id');
    }

    public function expenseAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'expense_account_id');
    }

    public function assets(): HasMany
    {
        return $this->hasMany(FixedAsset::class);
    }
}
