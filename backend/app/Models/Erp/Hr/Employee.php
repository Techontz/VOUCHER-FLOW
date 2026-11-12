<?php

namespace App\Models\Erp\Hr;

use App\Models\Department;
use App\Models\User;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

/**
 * The HR profile of a person who works for the company: one-to-one with a
 * user when the person signs in, standing alone when they do not.
 */
class Employee extends HrModel
{
    public const STATUS_ACTIVE = 'active';

    public const STATUS_SUSPENDED = 'suspended';

    public const STATUS_EXITED = 'exited';

    public const STATUSES = [self::STATUS_ACTIVE, self::STATUS_SUSPENDED, self::STATUS_EXITED];

    public const EMPLOYMENT_TYPES = ['permanent', 'fixed_term', 'casual', 'intern'];

    protected $table = 'hr_employees';

    protected function hrCasts(): array
    {
        return [
            'user_id' => 'integer',
            'department_id' => 'integer',
            'manager_id' => 'integer',
            'shift_id' => 'integer',
            'created_by' => 'integer',
            'date_of_birth' => 'date',
            'hire_date' => 'date',
            'probation_end' => 'date',
            'exit_date' => 'date',
            'heslb_beneficiary' => 'boolean',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function manager(): BelongsTo
    {
        return $this->belongsTo(self::class, 'manager_id');
    }

    public function shift(): BelongsTo
    {
        return $this->belongsTo(Shift::class);
    }

    public function contracts(): HasMany
    {
        return $this->hasMany(Contract::class);
    }

    public function activeContract(): HasOne
    {
        return $this->hasOne(Contract::class)->where('status', Contract::STATUS_ACTIVE)->latestOfMany('start_date');
    }

    public function movements(): HasMany
    {
        return $this->hasMany(Movement::class);
    }

    public function onboardingTasks(): HasMany
    {
        return $this->hasMany(OnboardingTask::class)->orderBy('sort');
    }

    public function isActive(): bool
    {
        return $this->status === self::STATUS_ACTIVE;
    }
}
