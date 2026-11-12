<?php

namespace App\Models\Erp\Hr;

/**
 * One version of a statutory rule (PAYE bands, NSSF, WCF, SDL, HESLB) for a
 * country, in force from its effective date until a later version replaces it.
 */
class StatutoryRate extends HrModel
{
    public const KIND_PERCENT = 'percent';

    public const KIND_BANDS = 'bands';

    protected $table = 'hr_statutory_rates';

    protected function hrCasts(): array
    {
        return ['rate' => 'decimal:4', 'bands' => 'array', 'effective_from' => 'date', 'created_by' => 'integer'];
    }
}
