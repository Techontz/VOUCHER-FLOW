<?php

namespace App\Models\Erp;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use App\Services\Erp\JournalPoster;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use LogicException;

/**
 * A posted journal entry. Only its status may change (posted → reversed), and
 * only by {@see JournalPoster::reverse()}; amounts, dates and
 * lines are fixed once written, and the entry can never be deleted.
 */
class JournalEntry extends Model
{
    use BelongsToTenant;

    public const STATUS_POSTED = 'posted';

    public const STATUS_REVERSED = 'reversed';

    protected $guarded = ['id'];

    protected static function booted(): void
    {
        static::updating(function (self $entry) {
            if (array_diff(array_keys($entry->getDirty()), ['status', 'updated_at'])) {
                throw new LogicException('A posted journal entry cannot be edited; reverse it instead.');
            }
        });
        static::deleting(fn () => throw new LogicException('A posted journal entry cannot be deleted; reverse it instead.'));
    }

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'source_id' => 'integer',
            'reversal_of_id' => 'integer',
            'created_by' => 'integer',
            'entry_date' => 'date',
            'posted_at' => 'datetime',
            'total' => 'decimal:2',
        ];
    }

    public function lines(): HasMany
    {
        return $this->hasMany(JournalLine::class);
    }

    public function reversalOf(): BelongsTo
    {
        return $this->belongsTo(self::class, 'reversal_of_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
