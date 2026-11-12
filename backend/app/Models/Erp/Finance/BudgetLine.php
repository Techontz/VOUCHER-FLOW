<?php

namespace App\Models\Erp\Finance;

use App\Models\Erp\Account;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Tenancy comes through the budget. */
class BudgetLine extends Model
{
    protected $guarded = ['id'];

    protected function casts(): array
    {
        return ['budget_id' => 'integer', 'account_id' => 'integer', 'month' => 'integer', 'amount' => 'decimal:2'];
    }

    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }
}
