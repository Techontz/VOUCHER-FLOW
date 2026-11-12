<?php

namespace App\Http\Controllers\Api\Erp\Documents;

use App\Http\Controllers\Controller;
use App\Models\Erp\Documents\Document;
use App\Models\Erp\Documents\DocumentLink;
use App\Models\Erp\Documents\DocumentVersion;
use App\Models\Erp\Documents\Folder;
use App\Services\AuditLogger;
use App\Services\Erp\Documents\DocumentAccess;
use App\Services\Erp\Documents\DocumentStore;
use App\Support\Erp\Permissions;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use RuntimeException;
use Symfony\Component\HttpFoundation\Response;

/**
 * Documents: upload, versions, metadata, access, retention, links and the
 * one way bytes leave the store, download(), which checks access and writes
 * the access log on every call. A document the caller may not open answers
 * 404, exactly like another company's.
 */
class DocumentController extends Controller
{
    public function __construct(
        private readonly TenantContext $tenant,
        private readonly DocumentAccess $access,
        private readonly DocumentStore $store,
        private readonly AuditLogger $audit,
        private readonly Permissions $permissions,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $trashed = $request->boolean('deleted');

        abort_if($trashed && ! $this->access->manages($user), 403, 'Only a documents manager can see deleted documents.');

        return response()->json($this->access->scope(Document::query(), $user)
            ->when($trashed, fn ($q) => $q->onlyTrashed())
            ->with(['folder:id,name', 'owner:id,name', 'latestVersion'])
            ->when($request->has('folder_id'), fn ($q) => $q->where('folder_id', $request->integer('folder_id') ?: null))
            ->when($request->query('document_type'), fn ($q, $v) => $q->where('document_type', $v))
            ->when($request->query('tag'), fn ($q, $v) => $q->whereJsonContains('tags', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                ->where('title', 'like', "%{$v}%")->orWhere('reference', 'like', "%{$v}%")->orWhere('description', 'like', "%{$v}%")))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    /** Documents expiring within the window (default 30 days), and those already expired. */
    public function expiring(Request $request): JsonResponse
    {
        $days = max(1, min((int) $request->query('days', 30), 365));

        $rows = $this->access->scope(Document::query(), $request->user())
            ->with(['folder:id,name', 'owner:id,name'])
            ->whereNotNull('expires_on')
            ->where('expires_on', '<=', today()->addDays($days))
            ->when(! $request->boolean('include_expired', true), fn ($q) => $q->where('expires_on', '>=', today()))
            ->orderBy('expires_on')
            ->limit(200)
            ->get()
            ->map(fn (Document $d) => [...$d->toArray(), 'days_left' => (int) today()->diffInDays($d->expires_on, false)]);

        return response()->json(['data' => $rows, 'days' => $days]);
    }

    /** Documents linked to one record, for the files panel other modules embed. */
    public function linked(Request $request): JsonResponse
    {
        $data = $request->validate([
            'type' => ['required', 'string', 'regex:/^[a-z][a-z_]{1,39}$/'],
            'id' => ['required', 'integer', 'min:1'],
        ]);

        return response()->json(['data' => $this->access->scope(Document::query(), $request->user())
            ->whereHas('links', fn ($q) => $q->where('attachable_type', $data['type'])->where('attachable_id', $data['id']))
            ->with(['latestVersion', 'owner:id,name'])
            ->latest('id')->limit(100)->get()]);
    }

    public function show(Request $request, Document $document): JsonResponse
    {
        $user = $request->user();
        $this->authorizeDocument($request, $document);
        // A screen refreshing itself after an edit is not another viewing.
        if (! $request->boolean('refresh')) {
            $this->store->logAccess($document, $document->current_version, 'view', $user);
        }

        $document->load([
            'folder', 'owner:id,name', 'creator:id,name',
            'versions' => fn ($q) => $q->with('uploader:id,name'),
            'links',
        ]);

        $manages = $this->access->manages($user);

        return response()->json(['data' => [
            ...$document->toArray(),
            'breadcrumbs' => $document->folder ? $document->folder->path() : [],
            'retained' => $document->isRetained(),
            'access_log' => $manages
                ? $document->accessLogs()->with('user:id,name')->limit(50)->get()
                : [],
            'can' => [
                'upload' => $this->permissions->allows($user, 'documents.upload'),
                'manage' => $manages,
                'delete' => $this->permissions->allows($user, 'documents.delete') && ! $document->isRetained(),
            ],
        ]]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        $data = $this->metadata($request);
        $request->validate(['file' => $this->fileRules()], $this->fileMessages());
        $links = $this->linkRules($request);

        if (! empty($data['folder_id'])) {
            abort_unless($this->access->canSeeFolder(Folder::query()->findOrFail($data['folder_id']), $user), 404);
        }

        // Narrowing access and setting retention at upload is the manager's call.
        if (! $this->access->manages($user)) {
            unset($data['retention_years']);
        }

        $document = $this->store->create($data, $request->file('file'), $links, $user);

        return response()->json(['data' => $document->load('latestVersion', 'links')], 201);
    }

    public function update(Request $request, Document $document): JsonResponse
    {
        $user = $request->user();
        $this->authorizeDocument($request, $document);
        $this->assertEditor($request, $document);

        $data = $this->metadata($request, true);
        unset($data['retention_years']);

        if (! $this->access->manages($user)) {
            unset($data['access_scope'], $data['access_roles'], $data['access_users']);
        }

        if (! empty($data['folder_id'])) {
            abort_unless($this->access->canSeeFolder(Folder::query()->findOrFail($data['folder_id']), $user), 404);
        }

        $before = $document->only(array_keys($data));
        $document->update($data);
        $this->audit->log('document.updated', "Updated {$document->title}", $document, $before, $document->only(array_keys($data)));

        return response()->json(['data' => $document->fresh(['folder', 'latestVersion', 'links'])]);
    }

    public function retention(Request $request, Document $document): JsonResponse
    {
        $this->authorizeDocument($request, $document);
        $years = $request->validate(['retention_years' => ['nullable', 'integer', 'min:1', 'max:100']])['retention_years'] ?? null;

        return response()->json(['data' => $this->store->setRetention($document, $years, $request->user())]);
    }

    public function addVersion(Request $request, Document $document): JsonResponse
    {
        $this->authorizeDocument($request, $document);
        $this->assertEditor($request, $document);
        $request->validate(['file' => $this->fileRules(), 'note' => ['nullable', 'string', 'max:255']], $this->fileMessages());

        $version = $this->store->addVersion($document, $request->file('file'), $request->input('note'), $request->user());

        return response()->json(['data' => $version->load('uploader:id,name')], 201);
    }

    /** Streams one version (the current one unless ?version= names another). */
    public function download(Request $request, Document $document): Response
    {
        $this->authorizeDocument($request, $document);

        $number = $request->integer('version') ?: $document->current_version;
        $version = DocumentVersion::query()->where('document_id', $document->id)->where('version', $number)->firstOrFail();

        $disk = Storage::disk($version->disk ?: DocumentStore::DISK);
        abort_unless($disk->exists($version->path), 404, 'That file is no longer stored.');

        $this->store->logAccess($document, $version->version, $request->boolean('inline') ? 'preview' : 'download', $request->user());

        $headers = ['Content-Type' => $version->mime_type ?: 'application/octet-stream', 'X-Content-Type-Options' => 'nosniff'];

        return $request->boolean('inline')
            ? $disk->response($version->path, $version->original_name, $headers)
            : $disk->download($version->path, $version->original_name, $headers);
    }

    public function addLink(Request $request, Document $document): JsonResponse
    {
        $this->authorizeDocument($request, $document);
        $data = $request->validate([
            'type' => ['required', 'string', 'regex:/^[a-z][a-z_]{1,39}$/'],
            'id' => ['required', 'integer', 'min:1'],
        ]);

        return response()->json(['data' => $this->store->link($document, $data['type'], $data['id'], $request->user())], 201);
    }

    public function removeLink(Request $request, Document $document, DocumentLink $link): JsonResponse
    {
        $this->authorizeDocument($request, $document);
        abort_unless($link->document_id === $document->id, 404);
        $this->store->unlink($document, $link, $request->user());

        return response()->json(['message' => 'Link removed.']);
    }

    public function destroy(Request $request, Document $document): JsonResponse
    {
        $this->authorizeDocument($request, $document);
        $this->store->delete($document, $request->user());

        return response()->json(['message' => "{$document->title} deleted."]);
    }

    public function restore(Request $request, Document $document): JsonResponse
    {
        return response()->json(['data' => $this->store->restore($document, $request->user())]);
    }

    private function authorizeDocument(Request $request, Document $document): void
    {
        abort_unless($this->access->canSee($document, $request->user()), 404);
    }

    /** Metadata is edited by whoever uploaded the document, or a documents manager. */
    private function assertEditor(Request $request, Document $document): void
    {
        $user = $request->user();

        if ($document->created_by !== $user->id && $document->owner_id !== $user->id && ! $this->access->manages($user)) {
            throw new RuntimeException('Only the person who uploaded this document or a documents manager can change it.');
        }
    }

    private function fileRules(): array
    {
        $extensions = implode(',', Document::EXTENSIONS);

        return ['required', 'file', 'max:'.Document::MAX_UPLOAD_KB, "extensions:{$extensions}", "mimes:{$extensions}"];
    }

    private function fileMessages(): array
    {
        return [
            'file.max' => 'A document must be 20 MB or smaller.',
            'file.extensions' => 'Upload a PDF, an image, an office document or a CSV file.',
            'file.mimes' => 'The file\'s content does not match an allowed type (PDF, image, office document or CSV).',
        ];
    }

    /** @return list<array{type: string, id: int}> */
    private function linkRules(Request $request): array
    {
        return array_values($request->validate([
            'links' => ['nullable', 'array', 'max:20'],
            'links.*.type' => ['required', 'string', 'regex:/^[a-z][a-z_]{1,39}$/'],
            'links.*.id' => ['required', 'integer', 'min:1'],
        ])['links'] ?? []);
    }

    private function metadata(Request $request, bool $partial = false): array
    {
        $company = $this->tenant->id();

        // A multipart form sends tags as "a, b" or tags[]; both become a clean list.
        if (is_string($request->input('tags'))) {
            $request->merge(['tags' => array_values(array_filter(array_map('trim', explode(',', $request->input('tags')))))]);
        }

        $data = $request->validate([
            'title' => [$partial ? 'sometimes' : 'nullable', 'string', 'max:180'],
            'folder_id' => ['sometimes', 'nullable', 'integer', Rule::exists('dms_folders', 'id')->where('company_id', $company)],
            'document_type' => ['sometimes', Rule::in(Document::TYPES)],
            'tags' => ['nullable', 'array', 'max:20'],
            'tags.*' => ['string', 'max:40'],
            'description' => ['nullable', 'string', 'max:5000'],
            'reference' => ['nullable', 'string', 'max:80'],
            'issued_on' => ['nullable', 'date'],
            'expires_on' => ['nullable', 'date', 'after_or_equal:issued_on'],
            'access_scope' => ['sometimes', Rule::in(Document::SCOPES)],
            'access_roles' => ['nullable', 'array'],
            'access_roles.*' => ['string', 'max:60'],
            'access_users' => ['nullable', 'array'],
            'access_users.*' => ['integer', Rule::exists('users', 'id')->where('company_id', $company)],
            'retention_years' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);

        if (isset($data['access_users'])) {
            $data['access_users'] = array_values(array_unique(array_map('intval', $data['access_users'])));
        }

        if (! $partial && empty($data['title'])) {
            $data['title'] = pathinfo((string) $request->file('file')?->getClientOriginalName(), PATHINFO_FILENAME) ?: 'Untitled document';
        }

        return $data;
    }
}
