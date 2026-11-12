<?php

namespace App\Models\Erp\Hr;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A staff loan or salary advance, recovered from payroll in instalments. */
class Loan extends HrModel
{
    public const TYPES = ['loan', 'advance'];

    public const STATUS_ACTIVE = 'active';

    public const STATUS_SETTLED = 'settled';

    public const STATUS_CANCELLED = 'cancelled';

    protected $table = 'hr_loans';

    protected function hrCasts(): array
    {
        return [
            'employee_id' => 'integer',
            'created_by' => 'integer',
            'principal' => 'decimal:2',
            'installment' => 'decimal:2',
            'balance' => 'decimal:2',
            'issued_on' => 'date',
        ];
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }

    public function repayments(): HasMany
    {
        return $this->hasMany(LoanRepayment::class)->orderBy('period');
    }

    /**
     * The months still to come and what each will recover, from the next
     * unpaid period until the balance is gone.
     *
     * @return list<array{period: string, amount: float, balance_after: float}>
     */
    public function schedule(): array
    {
        $balance = (float) $this->balance;
        $installment = (float) $this->installment;
        $last = $this->repayments()->max('period');
        $period = $last ? self::nextPeriod($last) : $this->start_period;
        $rows = [];

        while ($balance > 0.004 && $installment > 0 && count($rows) < 120) {
            $amount = round(min($installment, $balance), 2);
            $balance = round($balance - $amount, 2);
            $rows[] = ['period' => $period, 'amount' => $amount, 'balance_after' => $balance];
            $period = self::nextPeriod($period);
        }

        return $rows;
    }

    public static function nextPeriod(string $period): string
    {
        return date('Y-m', strtotime($period.'-01 +1 month'));
    }
}
