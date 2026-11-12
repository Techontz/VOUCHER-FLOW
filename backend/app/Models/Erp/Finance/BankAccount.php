<?php

namespace App\Models\Erp\Finance;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Account;
use App\Models\Erp\JournalEntry;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A bank, mobile money or cash account: the details a person needs to pay
 * into it, and the ledger account (1201-1299) its money is counted on. The
 * balance always comes from the journal, never from this row.
 */
class BankAccount extends Model
{
    use BelongsToTenant;

    public const TYPES = ['bank', 'mobile_money', 'cash'];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'account_id' => 'integer',
            'opening_entry_id' => 'integer',
            'opening_balance' => 'decimal:2',
            'opening_date' => 'date',
            'is_active' => 'boolean',
        ];
    }

    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    public function openingEntry(): BelongsTo
    {
        return $this->belongsTo(JournalEntry::class, 'opening_entry_id');
    }
}
