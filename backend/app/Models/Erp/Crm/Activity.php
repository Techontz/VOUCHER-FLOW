<?php

namespace App\Models\Erp\Crm;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Customer;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A call, meeting, visit or task, usually with a due date, linked to a lead,
 * an opportunity or a customer. An open one past its due date is an overdue
 * follow-up.
 */
class Activity extends Model
{
    use BelongsToTenant, OwnedByUser;

    protected $table = 'crm_activities';

    public const TYPES = ['call', 'meeting', 'visit', 'task'];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'lead_id' => 'integer',
            'opportunity_id' => 'integer',
            'customer_id' => 'integer',
            'owner_id' => 'integer',
            'created_by' => 'integer',
            'completed_by' => 'integer',
            'due_at' => 'datetime',
            'completed_at' => 'datetime',
        ];
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_id');
    }

    public function lead(): BelongsTo
    {
        return $this->belongsTo(Lead::class);
    }

    public function opportunity(): BelongsTo
    {
        return $this->belongsTo(Opportunity::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }
}
