<?php

namespace App\Models\Erp\Crm;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Customer;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Someone who might buy. A qualified lead converts once, into a customer and
 * an opportunity; after that it is history and the opportunity carries on.
 */
class Lead extends Model
{
    use BelongsToTenant, OwnedByUser;

    protected $table = 'crm_leads';

    public const STATUS_NEW = 'new';

    public const STATUS_CONTACTED = 'contacted';

    public const STATUS_QUALIFIED = 'qualified';

    public const STATUS_LOST = 'lost';

    public const STATUS_CONVERTED = 'converted';

    /** The statuses a person may set by hand; converted is reached only by converting. */
    public const STATUSES = [self::STATUS_NEW, self::STATUS_CONTACTED, self::STATUS_QUALIFIED, self::STATUS_LOST];

    public const SOURCES = ['referral', 'walk_in', 'phone', 'website', 'social_media', 'trade_show', 'field_visit', 'other'];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'owner_id' => 'integer',
            'customer_id' => 'integer',
            'opportunity_id' => 'integer',
            'created_by' => 'integer',
            'converted_by' => 'integer',
            'estimated_value' => 'decimal:2',
            'converted_at' => 'datetime',
        ];
    }

    public function isConverted(): bool
    {
        return $this->status === self::STATUS_CONVERTED;
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_id');
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function opportunity(): BelongsTo
    {
        return $this->belongsTo(Opportunity::class);
    }

    public function activities(): HasMany
    {
        return $this->hasMany(Activity::class);
    }
}
