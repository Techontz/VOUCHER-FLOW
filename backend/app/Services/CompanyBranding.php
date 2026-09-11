<?php

namespace App\Services;

use App\Models\Company;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

/**
 * Stores and removes a company's artwork.
 *
 * One path for every caller — a tenant editing its own branding, a super admin
 * setting up someone else's, and the demo seeder — because a logo that lands in
 * a different place depending on who uploaded it is a logo that will eventually
 * fail to render for somebody.
 *
 * Files go on the `public` disk under a per-tenant prefix with a random name.
 * The prefix keeps one company's artwork out of another's directory; the random
 * name means a URL cannot be guessed from the company id, and replacing a logo
 * produces a new URL rather than a stale cached one.
 */
class CompanyBranding
{
    public const SLOT_LOGO = 'logo';

    public const SLOT_MARK = 'logo_mark';

    private const COLUMN = [
        self::SLOT_LOGO => 'logo_path',
        self::SLOT_MARK => 'logo_mark_path',
    ];

    public function __construct(private readonly AuditLogger $audit) {}

    /** @return string the stored path */
    public function store(Company $company, UploadedFile $file, string $slot = self::SLOT_LOGO): string
    {
        $column = self::COLUMN[$slot] ?? self::COLUMN[self::SLOT_LOGO];

        $this->deleteFile($company->{$column});

        $name = Str::random(40).'.'.$this->extension($file);
        $path = $file->storeAs($this->directory($company), $name, 'public');

        $company->forceFill([$column => $path])->save();

        $this->audit->log(
            'company.logo_updated',
            ($slot === self::SLOT_MARK ? 'Square mark' : 'Logo')." updated for {$company->name}",
            $company,
        );

        return $path;
    }

    public function remove(Company $company, string $slot = self::SLOT_LOGO): void
    {
        $column = self::COLUMN[$slot] ?? self::COLUMN[self::SLOT_LOGO];

        if (! $company->{$column}) {
            return;
        }

        $this->deleteFile($company->{$column});
        $company->forceFill([$column => null])->save();

        $this->audit->log(
            'company.logo_removed',
            ($slot === self::SLOT_MARK ? 'Square mark' : 'Logo')." removed from {$company->name}",
            $company,
        );
    }

    /**
     * Publishes artwork that is already on disk — the demo seeder's path.
     * Same destination and same columns as an upload, so seeded branding and
     * uploaded branding are indistinguishable afterwards.
     */
    public function publishFile(Company $company, string $absolutePath, string $slot = self::SLOT_LOGO): ?string
    {
        if (! is_readable($absolutePath)) {
            return null;
        }

        $column = self::COLUMN[$slot] ?? self::COLUMN[self::SLOT_LOGO];
        $path = $this->directory($company).'/'.Str::random(40).'.'.pathinfo($absolutePath, PATHINFO_EXTENSION);

        Storage::disk('public')->put($path, file_get_contents($absolutePath));
        $company->forceFill([$column => $path])->save();

        return $path;
    }

    private function directory(Company $company): string
    {
        return "companies/{$company->id}/branding";
    }

    /**
     * Never trust the client's filename for the extension. The guessed
     * extension comes from the file's own content, so a `.png` that is really
     * something else is stored under what it actually is.
     */
    private function extension(UploadedFile $file): string
    {
        $guessed = strtolower((string) $file->guessExtension());

        return in_array($guessed, ['png', 'jpg', 'jpeg', 'webp'], true) ? $guessed : 'png';
    }

    private function deleteFile(?string $path): void
    {
        if ($path && Storage::disk('public')->exists($path)) {
            Storage::disk('public')->delete($path);
        }
    }
}
