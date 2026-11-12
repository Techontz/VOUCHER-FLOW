<?php

namespace App\Models\Erp\Procurement;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One person's decision on a requisition, order or invoice variance, kept for good. */
class ProcurementApproval extends Model
{
    use BelongsToTenant;

    public const APPROVED = 'approved';

    public const REJECTED = 'rejected';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'approvable_id' => 'integer',
            'level' => 'integer',
            'user_id' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
