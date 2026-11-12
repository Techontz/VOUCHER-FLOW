<?php

namespace App\Models\Erp\Hr;

use App\Models\User;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** One person's review for one period: objectives, ratings 1 to 5, and comments. */
class Appraisal extends HrModel
{
    public const STATUSES = ['draft', 'submitted', 'completed'];

    protected $table = 'hr_appraisals';

    protected function hrCasts(): array
    {
        return [
            'period_id' => 'integer',
            'employee_id' => 'integer',
            'reviewer_id' => 'integer',
            'overall_rating' => 'decimal:2',
            'completed_at' => 'datetime',
        ];
    }

    public function period(): BelongsTo
    {
        return $this->belongsTo(AppraisalPeriod::class, 'period_id');
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }

    public function reviewer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewer_id');
    }

    public function objectives(): HasMany
    {
        return $this->hasMany(AppraisalObjective::class);
    }

    /** The weighted mean of the rated objectives, or null until one is rated. */
    public function weightedRating(): ?float
    {
        $rated = $this->objectives()->whereNotNull('rating')->get();
        $weight = $rated->sum('weight');

        return $weight > 0 ? round($rated->sum(fn ($o) => $o->rating * $o->weight) / $weight, 2) : null;
    }
}
