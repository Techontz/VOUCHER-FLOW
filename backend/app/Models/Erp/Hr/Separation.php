<?php

namespace App\Models\Erp\Hr;

use App\Models\User;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A person leaving: notice, clearance across departments, and final dues. */
class Separation extends HrModel
{
    public const TYPES = ['resignation', 'termination', 'retirement', 'end_of_contract', 'redundancy', 'death'];

    /** Final dues are salary data. */
    public const SALARY_FIELDS = ['leave_pay', 'other_dues', 'outstanding_loans', 'final_dues'];

    /** The clearance checklist every exit starts with, by area. */
    public const CLEARANCE = [
        ['Line department', 'Handover of duties and documents'],
        ['ICT', 'Laptop, phone and system accounts returned or closed'],
        ['Stores', 'Tools, uniform and protective gear returned'],
        ['Finance', 'Advances, loans and imprest settled'],
        ['HR', 'Exit interview held and ID card returned'],
    ];

    protected $table = 'hr_separations';

    protected function hrCasts(): array
    {
        return [
            'employee_id' => 'integer',
            'created_by' => 'integer',
            'completed_by' => 'integer',
            'notice_date' => 'date',
            'last_working_day' => 'date',
            'leave_days_payable' => 'decimal:2',
            'leave_pay' => 'decimal:2',
            'other_dues' => 'decimal:2',
            'outstanding_loans' => 'decimal:2',
            'final_dues' => 'decimal:2',
            'completed_at' => 'datetime',
        ];
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(ClearanceItem::class);
    }

    public function completer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'completed_by');
    }
}
