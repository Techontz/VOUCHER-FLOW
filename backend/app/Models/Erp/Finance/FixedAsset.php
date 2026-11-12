<?php

namespace App\Models\Erp\Finance;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Supplier;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * An asset on the register. Registered as a draft, capitalised once (the
 * acquisition posts), depreciated month by month, disposed of once.
 */
class FixedAsset extends Model
{
    use BelongsToTenant;

    public const STATUS_DRAFT = 'draft';

    public const STATUS_ACTIVE = 'active';

    public const STATUS_DISPOSED = 'disposed';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'asset_class_id' => 'integer',
            'custodian_user_id' => 'integer',
            'supplier_id' => 'integer',
            'funding_bank_account_id' => 'integer',
            'disposal_bank_account_id' => 'integer',
            'acquisition_entry_id' => 'integer',
            'disposal_entry_id' => 'integer',
            'acquisition_date' => 'date',
            'disposal_date' => 'date',
            'capitalised_at' => 'datetime',
            'cost' => 'decimal:2',
            'residual_value' => 'decimal:2',
            'accumulated_depreciation' => 'decimal:2',
            'disposal_proceeds' => 'decimal:2',
            'disposal_gain_loss' => 'decimal:2',
            'useful_life_months' => 'integer',
            'rate' => 'decimal:2',
        ];
    }

    public function bookValue(): float
    {
        return round((float) $this->cost - (float) $this->accumulated_depreciation, 2);
    }

    public function assetClass(): BelongsTo
    {
        return $this->belongsTo(AssetClass::class);
    }

    public function custodian(): BelongsTo
    {
        return $this->belongsTo(User::class, 'custodian_user_id');
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class);
    }

    public function fundingBankAccount(): BelongsTo
    {
        return $this->belongsTo(BankAccount::class, 'funding_bank_account_id');
    }

    public function disposalBankAccount(): BelongsTo
    {
        return $this->belongsTo(BankAccount::class, 'disposal_bank_account_id');
    }

    public function depreciationLines(): HasMany
    {
        return $this->hasMany(AssetDepreciationLine::class);
    }

    public function events(): HasMany
    {
        return $this->hasMany(AssetEvent::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
