<?php

namespace App\Models\Erp\Documents;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Ties a document to any record by type string and id (a customer, a
 * vehicle, an employee). No foreign key: the record may live in a module
 * that is not installed.
 */
class DocumentLink extends Model
{
    use BelongsToTenant;

    protected $table = 'dms_document_links';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'document_id' => 'integer',
            'attachable_id' => 'integer',
            'created_by' => 'integer',
        ];
    }

    public function document(): BelongsTo
    {
        return $this->belongsTo(Document::class);
    }
}
