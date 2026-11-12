<?php

namespace App\Models\Erp\Hr;

use App\Models\User;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class OnboardingTask extends HrModel
{
    /** The checklist every new hire starts with. */
    public const DEFAULTS = [
        'Signed contract on file',
        'NIDA, TIN and NSSF numbers recorded',
        'Bank account details recorded',
        'Workstation, tools and uniform issued',
        'System accounts created',
        'Health and safety induction',
        'Introduced to the team and supervisor',
    ];

    protected $table = 'hr_onboarding_tasks';

    protected function hrCasts(): array
    {
        return ['employee_id' => 'integer', 'sort' => 'integer', 'done_by' => 'integer', 'done_at' => 'datetime'];
    }

    public function doer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'done_by');
    }
}
