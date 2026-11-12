<?php

namespace App\Services\Erp\Documents;

use App\Models\Erp\Crm\Lead;
use App\Models\Erp\Crm\Opportunity;
use App\Models\Erp\Customer;
use App\Models\Erp\Documents\Document;
use App\Models\Erp\Documents\DocumentAccessLog;
use App\Models\Erp\Documents\DocumentLink;
use App\Models\Erp\Documents\DocumentVersion;
use App\Models\Erp\Documents\Folder;
use App\Models\Erp\Product;
use App\Models\Erp\StockDocument;
use App\Models\Erp\Supplier;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Models\Voucher;
use App\Services\AuditLogger;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Every change to a stored document: upload, new version, links, retention,
 * deletion and restore. Files go to the private 'local' disk under the
 * company's own directory and are never given a public URL.
 */
class DocumentStore
{
    public const DISK = 'local';

    /**
     * Record types whose ids are checked against the company's own rows. Any
     * other lower-case type ('vehicle', 'employee') is accepted as given, so a
     * module this one does not know can still link its records.
     */
    public const KNOWN_TYPES = [
        'customer' => Customer::class,
        'supplier' => Supplier::class,
        'product' => Product::class,
        'warehouse' => Warehouse::class,
        'stock_document' => StockDocument::class,
        'voucher' => Voucher::class,
        'lead' => Lead::class,
        'opportunity' => Opportunity::class,
    ];

    public function __construct(private readonly AuditLogger $audit) {}

    /**
     * @param  array<string, mixed>  $data
     * @param  list<array{type: string, id: int}>  $links
     */
    public function create(array $data, UploadedFile $file, array $links, User $actor): Document
    {
        return DB::transaction(function () use ($data, $file, $links, $actor) {
            $folder = isset($data['folder_id']) ? Folder::query()->findOrFail($data['folder_id']) : null;
            $years = $data['retention_years'] ?? $this->inheritedRetention($folder);

            $document = Document::create([
                ...$data,
                'retention_years' => $years,
                'retain_until' => $this->retainUntil($years, $data['issued_on'] ?? null),
                'current_version' => 1,
                'owner_id' => $actor->id,
                'created_by' => $actor->id,
            ]);

            $this->storeVersion($document, $file, 1, null, $actor);

            foreach ($links as $link) {
                $this->link($document, $link['type'], (int) $link['id'], $actor, audit: false);
            }

            $this->audit->log('document.uploaded', "Uploaded {$document->title}", $document, actor: $actor);

            return $document;
        });
    }

    public function addVersion(Document $document, UploadedFile $file, ?string $note, User $actor): DocumentVersion
    {
        return DB::transaction(function () use ($document, $file, $note, $actor) {
            // Locked so two uploads at once queue for the next number rather than collide.
            $locked = Document::query()->lockForUpdate()->findOrFail($document->id);
            $next = $locked->current_version + 1;

            $version = $this->storeVersion($locked, $file, $next, $note, $actor);
            $locked->update(['current_version' => $next]);

            $this->audit->log('document.version_added', "Uploaded version {$next} of {$locked->title}", $locked,
                ['current_version' => $next - 1], ['current_version' => $next], actor: $actor);

            return $version;
        });
    }

    public function link(Document $document, string $type, int $id, User $actor, bool $audit = true): DocumentLink
    {
        $class = self::KNOWN_TYPES[$type] ?? null;

        if ($class && ! $class::query()->whereKey($id)->exists()) {
            throw new RuntimeException('That record does not exist in this company.');
        }

        $link = DocumentLink::query()->firstOrCreate(
            ['document_id' => $document->id, 'attachable_type' => $type, 'attachable_id' => $id],
            ['created_by' => $actor->id],
        );

        if ($audit) {
            $this->audit->log('document.linked', "Linked {$document->title} to {$type} #{$id}", $document, actor: $actor);
        }

        return $link;
    }

    public function unlink(Document $document, DocumentLink $link, User $actor): void
    {
        $link->delete();
        $this->audit->log('document.unlinked', "Unlinked {$document->title} from {$link->attachable_type} #{$link->attachable_id}", $document, actor: $actor);
    }

    /**
     * Retention may be extended at any time; shortening it would let a record
     * be destroyed before the date it was promised to be kept until.
     */
    public function setRetention(Document $document, ?int $years, User $actor): Document
    {
        $until = $this->retainUntil($years, $document->issued_on?->toDateString() ?? $document->created_at->toDateString());

        if ($document->retain_until && (! $until || $until->lt($document->retain_until))) {
            throw new RuntimeException("{$document->title} must be kept until {$document->retain_until->toDateString()}. Retention can be extended, not shortened.");
        }

        $before = ['retain_until' => $document->retain_until?->toDateString()];
        $document->update(['retention_years' => $years, 'retain_until' => $until]);
        $this->audit->log('document.retention_changed', "Changed retention of {$document->title}", $document,
            $before, ['retain_until' => $until?->toDateString()], actor: $actor);

        return $document;
    }

    public function delete(Document $document, User $actor): void
    {
        DB::transaction(function () use ($document, $actor) {
            $locked = Document::query()->lockForUpdate()->findOrFail($document->id);

            if ($locked->isRetained()) {
                throw new RuntimeException("{$locked->title} is under retention until {$locked->retain_until->format('j M Y')} and cannot be deleted before then.");
            }

            $locked->forceFill(['deleted_by' => $actor->id])->save();
            $locked->delete();

            $this->audit->log('document.deleted', "Deleted {$locked->title}", $locked, actor: $actor);
        });
    }

    public function restore(Document $document, User $actor): Document
    {
        if (! $document->trashed()) {
            throw new RuntimeException("{$document->title} is not deleted.");
        }

        $document->restore();
        $document->forceFill(['deleted_by' => null])->save();
        $this->audit->log('document.restored', "Restored {$document->title}", $document, actor: $actor);

        return $document;
    }

    public function logAccess(Document $document, ?int $version, string $action, User $actor): void
    {
        DocumentAccessLog::create([
            'company_id' => $document->company_id,
            'document_id' => $document->id,
            'version' => $version,
            'user_id' => $actor->id,
            'action' => $action,
            'ip' => request()?->ip(),
        ]);
    }

    /** The nearest retention period set on this folder or one above it. */
    public function inheritedRetention(?Folder $folder): ?int
    {
        $seen = [];

        while ($folder && ! in_array($folder->id, $seen, true)) {
            if ($folder->retention_years) {
                return $folder->retention_years;
            }
            $seen[] = $folder->id;
            $folder = $folder->parent;
        }

        return null;
    }

    public function retainUntil(?int $years, ?string $from): ?Carbon
    {
        return $years ? Carbon::parse($from ?? today())->addYears($years)->startOfDay() : null;
    }

    private function storeVersion(Document $document, UploadedFile $file, int $number, ?string $note, User $actor): DocumentVersion
    {
        $extension = strtolower($file->getClientOriginalExtension() ?: ($file->guessExtension() ?? 'bin'));
        $path = $file->storeAs(
            "companies/{$document->company_id}/documents/{$document->id}",
            "v{$number}-".Str::random(24).".{$extension}",
            self::DISK,
        );

        if (! $path) {
            throw new RuntimeException('The file could not be stored. Please try again.');
        }

        return DocumentVersion::create([
            'company_id' => $document->company_id,
            'document_id' => $document->id,
            'version' => $number,
            'disk' => self::DISK,
            'path' => $path,
            'original_name' => mb_substr($file->getClientOriginalName(), 0, 255),
            'mime_type' => $file->getMimeType() ?: $file->getClientMimeType(),
            'size_bytes' => $file->getSize(),
            'checksum' => hash_file('sha256', $file->getRealPath()) ?: null,
            'note' => $note,
            'uploaded_by' => $actor->id,
        ]);
    }

    /** Writes generated bytes as a version, for demo data and imports. */
    public function storeContents(Document $document, string $contents, string $name, string $mime, int $number, User $actor): DocumentVersion
    {
        $path = "companies/{$document->company_id}/documents/{$document->id}/v{$number}-".Str::random(24).'.'.pathinfo($name, PATHINFO_EXTENSION);
        Storage::disk(self::DISK)->put($path, $contents);

        return DocumentVersion::create([
            'company_id' => $document->company_id, 'document_id' => $document->id, 'version' => $number,
            'disk' => self::DISK, 'path' => $path, 'original_name' => $name, 'mime_type' => $mime,
            'size_bytes' => strlen($contents), 'checksum' => hash('sha256', $contents), 'uploaded_by' => $actor->id,
        ]);
    }
}
