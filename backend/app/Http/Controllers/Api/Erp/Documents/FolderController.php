<?php

namespace App\Http\Controllers\Api\Erp\Documents;

use App\Http\Controllers\Controller;
use App\Models\Erp\Documents\Document;
use App\Models\Erp\Documents\Folder;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\Documents\DocumentAccess;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * The folder tree. Reading shows only folders the caller may open; shaping
 * the tree, its access and its retention is documents.manage.
 */
class FolderController extends Controller
{
    public function __construct(
        private readonly TenantContext $tenant,
        private readonly DocumentAccess $access,
        private readonly AuditLogger $audit,
    ) {}

    /** Every folder the caller may open, flat, for pickers and the tree. */
    public function index(Request $request): JsonResponse
    {
        $ids = $this->access->visibleFolderIds($request->user());

        return response()->json(['data' => Folder::query()->whereIn('id', $ids ?: [0])
            ->withCount('documents')->orderBy('name')
            ->get(['id', 'parent_id', 'name', 'access_scope', 'retention_years'])]);
    }

    /**
     * One level of the browser: the folder, the path down to it, the folders
     * inside it and the documents in it, each limited to what the caller may open.
     */
    public function browse(Request $request): JsonResponse
    {
        $user = $request->user();
        $folderId = $request->integer('folder_id') ?: null;
        $folder = null;

        if ($folderId) {
            $folder = Folder::query()->findOrFail($folderId);
            abort_unless($this->access->canSeeFolder($folder, $user), 404);
        }

        $visible = $this->access->visibleFolderIds($user);
        $children = Folder::query()->where('parent_id', $folderId)->whereIn('id', $visible ?: [0])
            ->withCount('documents')->orderBy('name')->get();

        $documents = $this->access->scope(Document::query(), $user)
            ->where('folder_id', $folderId)
            ->with(['owner:id,name', 'latestVersion'])
            ->when($request->query('q'), fn ($q, $v) => $q->where('title', 'like', "%{$v}%"))
            ->orderBy('title')
            ->paginate(min((int) $request->query('per_page', 50), 200));

        return response()->json([
            'folder' => $folder,
            'breadcrumbs' => $folder ? $folder->path() : [],
            'folders' => $children,
            'documents' => $documents,
        ]);
    }

    /** The roles and people access can be given to, for the access editor. */
    public function people(): JsonResponse
    {
        return response()->json([
            'roles' => array_map(fn (string $role) => ['key' => $role, 'label' => User::roleLabel($role)], User::assignableRoles()),
            'people' => User::query()->where('company_id', $this->tenant->id())->where('status', 'active')
                ->orderBy('name')->get(['id', 'name', 'role']),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->rules($request);
        $this->assertUniqueName($data['name'], $data['parent_id'] ?? null);

        $folder = Folder::create([...$data, 'created_by' => $request->user()->id]);
        $this->audit->log('document.folder_created', "Created folder {$folder->name}", $folder);

        return response()->json(['data' => $folder], 201);
    }

    public function update(Request $request, Folder $folder): JsonResponse
    {
        $data = $this->rules($request, $folder);

        if (array_key_exists('parent_id', $data) && $data['parent_id']) {
            $this->assertNotInside($folder, (int) $data['parent_id']);
        }

        if (isset($data['name'])) {
            $this->assertUniqueName($data['name'], array_key_exists('parent_id', $data) ? $data['parent_id'] : $folder->parent_id, $folder->id);
        }

        $before = $folder->only(array_keys($data));
        $folder->update($data);
        $this->audit->log('document.folder_updated', "Updated folder {$folder->name}", $folder, $before, $folder->only(array_keys($data)));

        return response()->json(['data' => $folder]);
    }

    public function destroy(Folder $folder): JsonResponse
    {
        if ($folder->children()->exists() || Document::withTrashed()->where('folder_id', $folder->id)->exists()) {
            throw new RuntimeException("{$folder->name} is not empty. Move or delete what is inside it first.");
        }

        $folder->delete();
        $this->audit->log('document.folder_deleted', "Deleted folder {$folder->name}", $folder);

        return response()->json(['message' => "{$folder->name} deleted."]);
    }

    private function assertNotInside(Folder $folder, int $parentId): void
    {
        $cursor = Folder::query()->find($parentId);

        while ($cursor) {
            if ($cursor->id === $folder->id) {
                throw new RuntimeException('A folder cannot be moved inside itself.');
            }
            $cursor = $cursor->parent;
        }
    }

    private function assertUniqueName(string $name, ?int $parentId, ?int $ignore = null): void
    {
        $taken = Folder::query()->where('parent_id', $parentId)->where('name', $name)
            ->when($ignore, fn ($q) => $q->whereKeyNot($ignore))->exists();

        if ($taken) {
            throw new RuntimeException("There is already a folder called {$name} here.");
        }
    }

    private function rules(Request $request, ?Folder $folder = null): array
    {
        $company = $this->tenant->id();
        $required = $folder ? 'sometimes' : 'required';

        $data = $request->validate([
            'name' => [$required, 'string', 'max:120', 'not_regex:/[\/\\\\]/'],
            'description' => ['nullable', 'string', 'max:255'],
            'parent_id' => ['sometimes', 'nullable', 'integer', Rule::exists('dms_folders', 'id')->where('company_id', $company)],
            'access_scope' => ['sometimes', Rule::in(Folder::SCOPES)],
            'access_roles' => ['nullable', 'array'],
            'access_roles.*' => ['string', 'max:60'],
            'access_users' => ['nullable', 'array'],
            'access_users.*' => ['integer', Rule::exists('users', 'id')->where('company_id', $company)],
            'retention_years' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);

        if (isset($data['access_users'])) {
            $data['access_users'] = array_values(array_unique(array_map('intval', $data['access_users'])));
        }

        return $data;
    }
}
