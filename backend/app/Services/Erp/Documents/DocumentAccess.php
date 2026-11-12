<?php

namespace App\Services\Erp\Documents;

use App\Models\Erp\Documents\Document;
use App\Models\Erp\Documents\Folder;
use App\Models\User;
use App\Support\Erp\Permissions;
use Illuminate\Database\Eloquent\Builder;

/**
 * Who may open what in the document store.
 *
 * A folder shares its contents with the whole company, with named roles or
 * with named people, and a sub-folder can only narrow what its parent allows.
 * A document inherits its folder's rule unless it narrows it further. The
 * person who uploaded a document always keeps it, and documents.manage sees
 * everything so a restricted folder can never be orphaned.
 */
class DocumentAccess
{
    /** @var array<string, list<int>> per-request memo of visible folder ids, keyed by user */
    private array $folders = [];

    public function __construct(private readonly Permissions $permissions) {}

    public function manages(User $user): bool
    {
        return $this->permissions->allows($user, 'documents.manage');
    }

    public function passes(?string $scope, ?array $roles, ?array $users, User $user): bool
    {
        return match ($scope) {
            'roles' => in_array($user->role, $roles ?? [], true),
            'users' => in_array($user->id, array_map('intval', $users ?? []), true),
            default => true,
        };
    }

    /** @return list<int> the folders this person may open (all of them for a manager) */
    public function visibleFolderIds(User $user): array
    {
        return $this->folders[$user->id.':'.$user->role] ??= $this->resolveFolders($user);
    }

    public function canSeeFolder(Folder $folder, User $user): bool
    {
        return in_array($folder->id, $this->visibleFolderIds($user), true);
    }

    public function canSee(Document $document, User $user): bool
    {
        if ($this->manages($user) || $document->created_by === $user->id) {
            return true;
        }

        if ($document->folder_id !== null && ! in_array($document->folder_id, $this->visibleFolderIds($user), true)) {
            return false;
        }

        return $this->passes($document->access_scope, $document->access_roles, $document->access_users, $user);
    }

    /** Constrains a document query to what this person may open. */
    public function scope(Builder $query, User $user): Builder
    {
        if ($this->manages($user)) {
            return $query;
        }

        $folders = $this->visibleFolderIds($user);

        return $query->where(fn (Builder $q) => $q
            ->where('dms_documents.created_by', $user->id)
            ->orWhere(fn (Builder $w) => $w
                ->where(fn (Builder $f) => $f->whereNull('dms_documents.folder_id')->orWhereIn('dms_documents.folder_id', $folders ?: [0]))
                ->where(fn (Builder $a) => $a
                    ->whereIn('dms_documents.access_scope', ['inherit', 'company'])
                    ->orWhere(fn (Builder $r) => $r->where('dms_documents.access_scope', 'roles')->whereJsonContains('dms_documents.access_roles', $user->role))
                    ->orWhere(fn (Builder $u) => $u->where('dms_documents.access_scope', 'users')->whereJsonContains('dms_documents.access_users', $user->id)))));
    }

    /** @return list<int> */
    private function resolveFolders(User $user): array
    {
        $all = Folder::query()->get(['id', 'parent_id', 'access_scope', 'access_roles', 'access_users'])->keyBy('id');

        if ($this->manages($user)) {
            return $all->keys()->map(fn ($id) => (int) $id)->values()->all();
        }

        $verdict = [];
        $visible = function (int $id) use (&$visible, &$verdict, $all, $user): bool {
            if (array_key_exists($id, $verdict)) {
                return $verdict[$id];
            }

            $folder = $all->get($id);
            // Guard against a cycle by assuming no while this folder is being decided.
            $verdict[$id] = false;

            return $verdict[$id] = $folder !== null
                && $this->passes($folder->access_scope, $folder->access_roles, $folder->access_users, $user)
                && ($folder->parent_id === null || $visible($folder->parent_id));
        };

        return $all->keys()->filter(fn ($id) => $visible((int) $id))->map(fn ($id) => (int) $id)->values()->all();
    }
}
