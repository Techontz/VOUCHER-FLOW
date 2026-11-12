<?php

namespace App\Services\Erp\Finance;

use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Whether a date falls in a closed month. Static so JournalPoster can ask it
 * without a dependency: one call at the top of post() keeps every module's
 * postings out of a closed period, not only Finance's own.
 *
 * The year-end closing entry is dated inside the year it closes, after some
 * of its months may already be closed; it alone runs inside bypass().
 */
class PeriodLock
{
    private static bool $bypassed = false;

    public static function assertOpen(?string $date, ?int $companyId = null): void
    {
        if (self::$bypassed) {
            return;
        }

        $period = self::closedPeriodFor($date, $companyId);

        if ($period !== null) {
            throw new RuntimeException(sprintf(
                '%s is closed, so nothing can be posted dated %s. Date the entry in an open month, or ask someone with period-closing rights to reopen it.',
                CarbonImmutable::createFromFormat('Y-m', $period)->startOfMonth()->format('F Y'),
                CarbonImmutable::parse($date)->format('j M Y'),
            ));
        }
    }

    public static function isClosed(?string $date, ?int $companyId = null): bool
    {
        return self::closedPeriodFor($date, $companyId) !== null;
    }

    /** Runs the callback with the lock lifted, for the year-end closing entry only. */
    public static function bypass(callable $callback): mixed
    {
        $before = self::$bypassed;
        self::$bypassed = true;

        try {
            return $callback();
        } finally {
            self::$bypassed = $before;
        }
    }

    private static function closedPeriodFor(?string $date, ?int $companyId): ?string
    {
        $companyId ??= app(TenantContext::class)->id();

        if (! $companyId) {
            return null;
        }

        $day = CarbonImmutable::parse($date ?? now()->toDateString())->toDateString();

        return DB::table('closed_periods')
            ->where('company_id', $companyId)
            ->where('status', 'closed')
            ->where('starts_on', '<=', $day)
            ->where('ends_on', '>=', $day)
            ->value('period');
    }
}
