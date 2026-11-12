<?php

namespace App\Models\Erp\Procurement;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;

/**
 * A company's procurement policy: when a second, senior approval is needed,
 * and how far receipts and invoices may stray from the order.
 */
class ProcurementSetting extends Model
{
    use BelongsToTenant;

    /** Roles whose approval counts as the senior one, unless the company says otherwise. */
    public const DEFAULT_SENIOR_ROLES = [User::ROLE_FINANCE, User::ROLE_DIRECTOR, User::ROLE_CEO, User::ROLE_COMPANY_ADMIN];

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'approval_threshold' => 'decimal:2',
            'senior_roles' => 'array',
            'receipt_tolerance_percent' => 'decimal:2',
            'price_tolerance_percent' => 'decimal:2',
            'quantity_tolerance_percent' => 'decimal:2',
            'default_vat_rate' => 'decimal:2',
        ];
    }

    /** The current company's settings, created with the defaults on first use. */
    public static function current(): self
    {
        return self::query()->firstOrCreate([], ['senior_roles' => self::DEFAULT_SENIOR_ROLES]);
    }

    /** @return list<string> */
    public function seniorRoles(): array
    {
        return $this->senior_roles ?: self::DEFAULT_SENIOR_ROLES;
    }
}
