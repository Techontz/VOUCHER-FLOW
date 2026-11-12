<?php

namespace App\Models\Erp\Hr;

use App\Models\Erp\Account;
use App\Models\Erp\JournalEntry;
use App\Models\User;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One month's payroll: draft -> authorised -> locked -> posted -> paid.
 * Only a draft can be recalculated; from authorisation on, the payslips are
 * what will be paid, and from locking on nothing about them can change.
 */
class PayrollRun extends HrModel
{
    public const STATUS_DRAFT = 'draft';

    public const STATUS_AUTHORISED = 'authorised';

    public const STATUS_LOCKED = 'locked';

    public const STATUS_POSTED = 'posted';

    public const STATUS_PAID = 'paid';

    /** The money columns a run totals from its payslips. */
    public const TOTALS = [
        'basic', 'allowances', 'overtime', 'other_earnings', 'absence_deduction', 'gross', 'nssf_employee', 'paye',
        'heslb', 'loans', 'other_deductions', 'total_deductions', 'net', 'nssf_employer', 'wcf', 'sdl',
    ];

    protected $table = 'hr_payroll_runs';

    protected function hrCasts(): array
    {
        $money = array_fill_keys(self::TOTALS, 'decimal:2');

        return [
            ...$money,
            'employees_count' => 'integer',
            'rates' => 'array',
            'period_start' => 'date',
            'period_end' => 'date',
            'payment_date' => 'date',
            'prepared_by' => 'integer',
            'authorised_by' => 'integer',
            'locked_by' => 'integer',
            'posted_by' => 'integer',
            'paid_by' => 'integer',
            'journal_entry_id' => 'integer',
            'payment_journal_id' => 'integer',
            'payment_account_id' => 'integer',
            'prepared_at' => 'datetime',
            'authorised_at' => 'datetime',
            'locked_at' => 'datetime',
            'posted_at' => 'datetime',
            'paid_at' => 'datetime',
        ];
    }

    public function payslips(): HasMany
    {
        return $this->hasMany(Payslip::class);
    }

    public function preparer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'prepared_by');
    }

    public function authoriser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'authorised_by');
    }

    public function locker(): BelongsTo
    {
        return $this->belongsTo(User::class, 'locked_by');
    }

    public function poster(): BelongsTo
    {
        return $this->belongsTo(User::class, 'posted_by');
    }

    public function payer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'paid_by');
    }

    public function journal(): BelongsTo
    {
        return $this->belongsTo(JournalEntry::class, 'journal_entry_id');
    }

    public function paymentJournal(): BelongsTo
    {
        return $this->belongsTo(JournalEntry::class, 'payment_journal_id');
    }

    public function paymentAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'payment_account_id');
    }

    /** Whether employees may see their payslips from this run. */
    public function isReleased(): bool
    {
        return in_array($this->status, [self::STATUS_LOCKED, self::STATUS_POSTED, self::STATUS_PAID], true);
    }
}
