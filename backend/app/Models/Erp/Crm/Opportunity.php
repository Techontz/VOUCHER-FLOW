<?php

namespace App\Models\Erp\Crm;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Customer;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A deal in the pipeline, valued in the company's currency and weighted by
 * its probability for the forecast. Won and lost are closing stages.
 */
class Opportunity extends Model
{
    use BelongsToTenant, OwnedByUser;

    protected $table = 'crm_opportunities';

    public const STAGE_PROSPECTING = 'prospecting';

    public const STAGE_PROPOSAL = 'proposal';

    public const STAGE_NEGOTIATION = 'negotiation';

    public const STAGE_WON = 'won';

    public const STAGE_LOST = 'lost';

    public const STAGES = [self::STAGE_PROSPECTING, self::STAGE_PROPOSAL, self::STAGE_NEGOTIATION, self::STAGE_WON, self::STAGE_LOST];

    public const OPEN_STAGES = [self::STAGE_PROSPECTING, self::STAGE_PROPOSAL, self::STAGE_NEGOTIATION];

    /** The probability a deal takes on entering a stage, unless the person sets their own. */
    public const DEFAULT_PROBABILITY = [
        self::STAGE_PROSPECTING => 10,
        self::STAGE_PROPOSAL => 40,
        self::STAGE_NEGOTIATION => 70,
        self::STAGE_WON => 100,
        self::STAGE_LOST => 0,
    ];

    /** Why deals close, kept to a short list so the win/loss report means something. */
    public const WIN_REASONS = ['price', 'quality', 'relationship', 'delivery', 'credit_terms', 'other'];

    public const LOSS_REASONS = ['price', 'competitor', 'no_budget', 'no_decision', 'timing', 'stock', 'other'];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'lead_id' => 'integer',
            'customer_id' => 'integer',
            'owner_id' => 'integer',
            'created_by' => 'integer',
            'probability' => 'integer',
            'value' => 'decimal:2',
            'expected_close_date' => 'date',
            'closed_at' => 'datetime',
            'stage_changed_at' => 'datetime',
        ];
    }

    public function isOpen(): bool
    {
        return in_array($this->stage, self::OPEN_STAGES, true);
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_id');
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function lead(): BelongsTo
    {
        return $this->belongsTo(Lead::class);
    }

    public function activities(): HasMany
    {
        return $this->hasMany(Activity::class);
    }
}
