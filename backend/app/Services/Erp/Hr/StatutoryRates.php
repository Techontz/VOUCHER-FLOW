<?php

namespace App\Services\Erp\Hr;

use App\Models\Erp\Hr\HrSetting;
use App\Models\Erp\Hr\StatutoryRate;
use Illuminate\Support\Carbon;
use RuntimeException;

/**
 * Statutory payroll rules as data. Each rule is a row with an effective date;
 * payroll asks which version was in force on the last day of the month it is
 * paying, so a budget change is a new row, never a code change, and past
 * months keep the rates they were paid on.
 *
 * DEFAULTS is only the starting data a company receives (Tanzania mainland),
 * written into its own table the first time payroll is used.
 */
class StatutoryRates
{
    public const CODES = ['paye', 'nssf_employee', 'nssf_employer', 'wcf', 'sdl', 'heslb'];

    /** @var array<string, list<array<string, mixed>>> */
    public const DEFAULTS = [
        'TZ' => [
            ['code' => 'paye', 'name' => 'PAYE (monthly bands)', 'kind' => 'bands', 'base' => 'taxable', 'party' => 'employee', 'rate' => null, 'bands' => [
                ['from' => 0, 'to' => 270000, 'base' => 0, 'rate' => 0],
                ['from' => 270000, 'to' => 520000, 'base' => 0, 'rate' => 8],
                ['from' => 520000, 'to' => 760000, 'base' => 20000, 'rate' => 20],
                ['from' => 760000, 'to' => 1000000, 'base' => 68000, 'rate' => 25],
                ['from' => 1000000, 'to' => null, 'base' => 128000, 'rate' => 30],
            ]],
            ['code' => 'nssf_employee', 'name' => 'NSSF, employee share', 'kind' => 'percent', 'base' => 'gross', 'party' => 'employee', 'rate' => 10],
            ['code' => 'nssf_employer', 'name' => 'NSSF, employer share', 'kind' => 'percent', 'base' => 'gross', 'party' => 'employer', 'rate' => 10],
            ['code' => 'wcf', 'name' => 'Workers Compensation Fund', 'kind' => 'percent', 'base' => 'gross', 'party' => 'employer', 'rate' => 0.5],
            ['code' => 'sdl', 'name' => 'Skills Development Levy', 'kind' => 'percent', 'base' => 'gross', 'party' => 'employer', 'rate' => 3.5],
            ['code' => 'heslb', 'name' => 'HESLB loan repayment', 'kind' => 'percent', 'base' => 'basic', 'party' => 'employee', 'rate' => 15],
        ],
    ];

    public const DEFAULT_EFFECTIVE_FROM = '2022-07-01';

    /** Writes the country's starting rates into the company's table, for any rule it has none of. */
    public function ensureDefaults(?string $country = null): void
    {
        $country ??= HrSetting::current()->country;
        $present = StatutoryRate::query()->where('country', $country)->distinct()->pluck('code')->all();

        foreach (self::DEFAULTS[$country] ?? [] as $row) {
            if (in_array($row['code'], $present, true)) {
                continue;
            }

            StatutoryRate::create([
                ...$row,
                'bands' => $row['bands'] ?? null,
                'country' => $country,
                'effective_from' => self::DEFAULT_EFFECTIVE_FROM,
            ]);
        }
    }

    /**
     * The version of every rule in force on a date.
     *
     * @return array<string, StatutoryRate>
     */
    public function inForce(Carbon|string $date, ?string $country = null): array
    {
        $country ??= HrSetting::current()->country;
        $this->ensureDefaults($country);
        $day = Carbon::parse($date)->toDateString();
        $rates = [];

        foreach (self::CODES as $code) {
            $rates[$code] = StatutoryRate::query()
                ->where('country', $country)->where('code', $code)
                ->whereDate('effective_from', '<=', $day)
                ->orderByDesc('effective_from')->orderByDesc('id')
                ->first()
                ?? throw new RuntimeException("No {$code} rate is in force for {$country} on {$day}. Add one under Statutory rates.");
        }

        return $rates;
    }

    /** Applies a percentage rule to its base, to the cent. */
    public static function percent(StatutoryRate $rate, float $base): float
    {
        return round(max(0, $base) * (float) $rate->rate / 100, 2);
    }

    /**
     * Tax on a monthly taxable amount under banded rules: the band's fixed
     * amount plus its rate on whatever lies above the band's floor.
     *
     * @param  list<array{from: float|int, to: float|int|null, base: float|int, rate: float|int}>  $bands
     */
    public static function banded(array $bands, float $taxable): float
    {
        if ($taxable <= 0) {
            return 0.0;
        }

        usort($bands, fn ($a, $b) => $a['from'] <=> $b['from']);

        foreach ($bands as $band) {
            $to = $band['to'] ?? null;

            if ($taxable > (float) $band['from'] && ($to === null || $taxable <= (float) $to)) {
                return round((float) $band['base'] + ($taxable - (float) $band['from']) * (float) $band['rate'] / 100, 2);
            }
        }

        return 0.0;
    }

    /** @return array<string, mixed> */
    public static function describe(StatutoryRate $rate): array
    {
        return [
            'code' => $rate->code, 'name' => $rate->name, 'kind' => $rate->kind, 'base' => $rate->base,
            'party' => $rate->party, 'rate' => $rate->rate !== null ? (float) $rate->rate : null,
            'bands' => $rate->bands, 'effective_from' => $rate->effective_from->toDateString(),
        ];
    }
}
