<?php

namespace App\Models\Erp\Finance;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Account;
use App\Models\Erp\JournalEntry;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A receipt or payment that no sale or purchase explains: owner capital,
 * rent, utilities, other income. A receipt posts Dr bank / Cr the chosen
 * account; a payment the mirror image.
 */
class CashbookEntry extends Model
{
    use BelongsToTenant;

    public const TYPE_RECEIPT = 'receipt';

    public const TYPE_PAYMENT = 'payment';

    public const TYPES = [self::TYPE_RECEIPT, self::TYPE_PAYMENT];

    public const PREFIXES = [self::TYPE_RECEIPT => 'CBR', self::TYPE_PAYMENT => 'CBP'];

    public const STATUS_DRAFT = 'draft';

    public const STATUS_POSTED = 'posted';

    public const STATUS_REVERSED = 'reversed';

    public const STATUS_CANCELLED = 'cancelled';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'bank_account_id' => 'integer',
            'account_id' => 'integer',
            'journal_entry_id' => 'integer',
            'entry_date' => 'date',
            'amount' => 'decimal:2',
            'posted_at' => 'datetime',
            'reversed_at' => 'datetime',
        ];
    }

    public function bankAccount(): BelongsTo
    {
        return $this->belongsTo(BankAccount::class);
    }

    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    public function journal(): BelongsTo
    {
        return $this->belongsTo(JournalEntry::class, 'journal_entry_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function poster(): BelongsTo
    {
        return $this->belongsTo(User::class, 'posted_by');
    }

    public function reverser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reversed_by');
    }
}
