<?php

namespace App\Services\Erp;

use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Sequential, per-company, per-year numbers for ERP documents: GRN-2026-000014.
 *
 * The sequence row is created if missing and then locked for the rest of the
 * caller's transaction, so concurrent postings queue here instead of racing
 * to the same number. Gaps can appear (a rolled-back transaction gives its
 * number back to nobody); duplicates cannot, and the documents' own unique
 * keys hold that line a second time.
 */
class DocumentNumberer
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function next(string $prefix, ?int $companyId = null): string
    {
        $companyId ??= $this->tenant->id() ?? throw new RuntimeException('No company is resolved for numbering.');
        $year = (int) now()->format('Y');

        return DB::transaction(function () use ($companyId, $prefix, $year) {
            DB::table('document_sequences')->insertOrIgnore([
                'company_id' => $companyId, 'key' => $prefix, 'year' => $year,
                'next_number' => 1, 'created_at' => now(), 'updated_at' => now(),
            ]);

            $row = DB::table('document_sequences')
                ->where(['company_id' => $companyId, 'key' => $prefix, 'year' => $year])
                ->lockForUpdate()
                ->first();

            $sequence = (int) $row->next_number;

            DB::table('document_sequences')->where('id', $row->id)
                ->update(['next_number' => $sequence + 1, 'updated_at' => now()]);

            return sprintf('%s-%d-%06d', $prefix, $year, $sequence);
        });
    }
}
