<?php

namespace App\Models\Erp\Documents;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A folder in the company's document tree. Its access applies to everything
 * inside it, including sub-folders: to open a document a person must pass
 * every folder above it as well as the document's own rule.
 */
class Folder extends Model
{
    use BelongsToTenant;

    protected $table = 'dms_folders';

    public const SCOPES = ['company', 'roles', 'users'];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'parent_id' => 'integer',
            'created_by' => 'integer',
            'retention_years' => 'integer',
            'access_roles' => 'array',
            'access_users' => 'array',
        ];
    }

    public function parent(): BelongsTo
    {
        return $this->belongsTo(self::class, 'parent_id');
    }

    public function children(): HasMany
    {
        return $this->hasMany(self::class, 'parent_id');
    }

    public function documents(): HasMany
    {
        return $this->hasMany(Document::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    /**
     * The breadcrumb from the top of the tree down to this folder.
     *
     * @return list<array{id: int, name: string}>
     */
    public function path(): array
    {
        $path = [];
        $seen = [];
        $folder = $this;

        while ($folder && ! in_array($folder->id, $seen, true)) {
            array_unshift($path, ['id' => $folder->id, 'name' => $folder->name]);
            $seen[] = $folder->id;
            $folder = $folder->parent;
        }

        return $path;
    }
}
