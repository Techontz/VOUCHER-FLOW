<?php

namespace App\Models\Erp\Hr;

use App\Models\User;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ClearanceItem extends HrModel
{
    protected $table = 'hr_clearance_items';

    protected function hrCasts(): array
    {
        return ['separation_id' => 'integer', 'department_id' => 'integer', 'cleared_by' => 'integer', 'cleared_at' => 'datetime'];
    }

    public function clearer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'cleared_by');
    }
}
