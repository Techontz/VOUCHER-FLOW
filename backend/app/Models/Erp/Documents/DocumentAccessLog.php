<?php

namespace App\Models\Erp\Documents;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Append-only: who viewed or downloaded which version, and when. */
class DocumentAccessLog extends Model
{
    use BelongsToTenant;

    public const UPDATED_AT = null;

    protected $table = 'dms_access_logs';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'document_id' => 'integer',
            'user_id' => 'integer',
            'version' => 'integer',
            'created_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
