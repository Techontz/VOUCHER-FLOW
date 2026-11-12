<?php

namespace App\Models\Erp\Fleet;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Account;
use App\Models\Erp\Supplier;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** A toll, parking fee, loading fee, allowance or other cost of a trip. */
class FleetTripExpense extends Model
{
    use BelongsToTenant;

    public const TYPES = ['allowance', 'toll', 'parking', 'loading', 'other'];

    /** The expense account each type is charged to at trip close. */
    public const ACCOUNTS = [
        'allowance' => 'fleet_allowances',
        'toll' => 'fleet_tolls',
        'parking' => 'fleet_tolls',
        'loading' => 'fleet_loading',
        'other' => 'fleet_trip_other',
    ];

    protected $table = 'fleet_trip_expenses';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'trip_id' => 'integer',
            'account_id' => 'integer',
            'supplier_id' => 'integer',
            'expense_date' => 'date:Y-m-d',
            'approved_at' => 'datetime',
        ];
    }

    public function trip(): BelongsTo
    {
        return $this->belongsTo(FleetTrip::class, 'trip_id');
    }

    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class);
    }

    public function recorder(): BelongsTo
    {
        return $this->belongsTo(User::class, 'recorded_by');
    }

    public function approver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'approved_by');
    }
}
