<?php

namespace App\Services\Erp\Finance;

use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;

/**
 * The company's fiscal year, from the fiscal_year_start setting ('MM-DD',
 * the day is taken as the 1st). Fiscal year 2026 is the year that starts in
 * 2026: with a July start, 1 Jul 2026 to 30 Jun 2027.
 */
class FiscalYear
{
    public static function startMonth(): int
    {
        $company = app(TenantContext::class)->company();
        $setting = $company ? (string) BusinessConfig::of($company)->setting('fiscal_year_start') : '01-01';
        $month = (int) explode('-', $setting)[0];

        return $month >= 1 && $month <= 12 ? $month : 1;
    }

    public static function start(int $year): CarbonImmutable
    {
        return CarbonImmutable::create($year, self::startMonth(), 1)->startOfDay();
    }

    public static function end(int $year): CarbonImmutable
    {
        return self::start($year)->addYear()->subDay();
    }

    /** The fiscal year a date belongs to. */
    public static function of(string|CarbonImmutable $date): int
    {
        $day = $date instanceof CarbonImmutable ? $date : CarbonImmutable::parse($date);

        return $day->month >= self::startMonth() ? $day->year : $day->year - 1;
    }

    /**
     * The twelve months of a fiscal year, as YYYY-MM.
     *
     * @return list<string>
     */
    public static function months(int $year): array
    {
        $start = self::start($year);

        return array_map(fn (int $i) => $start->addMonths($i)->format('Y-m'), range(0, 11));
    }
}
