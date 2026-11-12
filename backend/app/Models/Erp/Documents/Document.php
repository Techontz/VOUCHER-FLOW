<?php

namespace App\Models\Erp\Documents;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * A managed document: its metadata, who may open it, how long it must be
 * kept, and every version ever uploaded. The bytes live on the private disk
 * and leave only through DocumentController::download.
 */
class Document extends Model
{
    use BelongsToTenant, SoftDeletes;

    protected $table = 'dms_documents';

    /** 'inherit' follows the folder alone; the others narrow it further. */
    public const SCOPES = ['inherit', 'company', 'roles', 'users'];

    public const TYPES = [
        'general', 'contract', 'licence', 'permit', 'certificate', 'insurance', 'policy',
        'invoice', 'receipt', 'report', 'id_document', 'vehicle', 'hr', 'other',
    ];

    /** What may be uploaded, as file extensions; checked against the content as well. */
    public const EXTENSIONS = [
        'pdf', 'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic',
        'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'rtf', 'csv', 'txt',
    ];

    public const MAX_UPLOAD_KB = 20480;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'folder_id' => 'integer',
            'owner_id' => 'integer',
            'created_by' => 'integer',
            'deleted_by' => 'integer',
            'current_version' => 'integer',
            'retention_years' => 'integer',
            'tags' => 'array',
            'access_roles' => 'array',
            'access_users' => 'array',
            'issued_on' => 'date',
            'expires_on' => 'date',
            'retain_until' => 'date',
        ];
    }

    public function folder(): BelongsTo
    {
        return $this->belongsTo(Folder::class);
    }

    public function versions(): HasMany
    {
        return $this->hasMany(DocumentVersion::class)->orderByDesc('version');
    }

    public function latestVersion(): HasOne
    {
        return $this->hasOne(DocumentVersion::class)->ofMany('version', 'max');
    }

    public function links(): HasMany
    {
        return $this->hasMany(DocumentLink::class);
    }

    public function accessLogs(): HasMany
    {
        return $this->hasMany(DocumentAccessLog::class)->latest('id');
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function isRetained(): bool
    {
        return $this->retain_until !== null && $this->retain_until->isAfter(today());
    }
}
