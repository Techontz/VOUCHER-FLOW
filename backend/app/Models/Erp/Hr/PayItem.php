<?php

namespace App\Models\Erp\Hr;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * An earning (arrears, bonus) or deduction (union dues, insurance) a payroll
 * run picks up: once, when start and end period are the same, or every month
 * from the start period until the end period (open-ended when null).
 */
class PayItem extends HrModel
{
    public const KINDS = ['earning', 'deduction'];

    public const CATEGORIES = ['arrears', 'bonus', 'commission', 'other_earning', 'union', 'insurance', 'other_deduction'];

    protected $table = 'hr_pay_items';

    protected function hrCasts(): array
    {
        return ['employee_id' => 'integer', 'created_by' => 'integer', 'amount' => 'decimal:2', 'is_active' => 'boolean'];
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }

    public function scopeForPeriod(Builder $query, string $period): Builder
    {
        return $query->where('is_active', true)
            ->where('start_period', '<=', $period)
            ->where(fn ($q) => $q->whereNull('end_period')->orWhere('end_period', '>=', $period));
    }
}
