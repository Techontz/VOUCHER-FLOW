<?php

namespace App\Models\Erp\Finance;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One line of an asset's history: registered, capitalised, moved, depreciated, disposed. */
class AssetEvent extends Model
{
    use BelongsToTenant;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'fixed_asset_id' => 'integer',
            'event_date' => 'date',
            'amount' => 'decimal:2',
            'from_custodian_id' => 'integer',
            'to_custodian_id' => 'integer',
            'journal_entry_id' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function fromCustodian(): BelongsTo
    {
        return $this->belongsTo(User::class, 'from_custodian_id');
    }

    public function toCustodian(): BelongsTo
    {
        return $this->belongsTo(User::class, 'to_custodian_id');
    }
}
