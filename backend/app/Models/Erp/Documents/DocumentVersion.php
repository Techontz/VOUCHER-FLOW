<?php

namespace App\Models\Erp\Documents;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One upload of a document. Versions are never replaced: a new upload is a
 * new row, so the history of what was signed or certified stays intact.
 * The storage path is never sent to the client.
 */
class DocumentVersion extends Model
{
    use BelongsToTenant;

    protected $table = 'dms_document_versions';

    protected $guarded = ['id'];

    protected $hidden = ['path', 'disk'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'document_id' => 'integer',
            'version' => 'integer',
            'size_bytes' => 'integer',
            'uploaded_by' => 'integer',
        ];
    }

    public function document(): BelongsTo
    {
        return $this->belongsTo(Document::class);
    }

    public function uploader(): BelongsTo
    {
        return $this->belongsTo(User::class, 'uploaded_by');
    }
}
