<?php

namespace App\Models\Erp\Hr;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

class LoanRepayment extends HrModel
{
    protected $table = 'hr_loan_repayments';

    protected function hrCasts(): array
    {
        return ['loan_id' => 'integer', 'payroll_run_id' => 'integer', 'amount' => 'decimal:2', 'balance_after' => 'decimal:2'];
    }

    public function loan(): BelongsTo
    {
        return $this->belongsTo(Loan::class);
    }
}
