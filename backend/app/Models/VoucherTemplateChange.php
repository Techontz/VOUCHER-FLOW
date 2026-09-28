<?php

namespace App\Models;

use App\Support\VoucherTemplates;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One change of a company's voucher design — who made it, from where, and
 * whether it spent one of the company's own changes. Append-only: rows are
 * written by VoucherTemplateManager and never edited.
 */
class VoucherTemplateChange extends Model
{
    public const SOURCE_REGISTRATION = 'registration';

    public const SOURCE_COMPANY_ADMIN = 'company_admin';

    public const SOURCE_SUPER_ADMIN = 'super_admin';

    public const SOURCE_PLATFORM_CREATE = 'platform_create';

    public const UPDATED_AT = null;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return ['counted' => 'boolean'];
    }

    public function company(): BelongsTo
    {
        return $this->belongsTo(Company::class);
    }

    public function changedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'changed_by');
    }

    /** @return array<string, mixed> */
    public function toApi(): array
    {
        return [
            'id' => $this->id,
            'previous_template' => $this->previous_template,
            'previous_template_name' => $this->previous_template ? VoucherTemplates::name($this->previous_template) : null,
            'new_template' => $this->new_template,
            'new_template_name' => VoucherTemplates::name($this->new_template),
            'changed_by' => $this->changed_by,
            'changed_by_name' => $this->changed_by_name,
            'changed_by_role' => $this->changed_by_role,
            'source' => $this->source,
            'reason' => $this->reason,
            'counted' => $this->counted,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
