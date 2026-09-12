<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Workflow extends Model
{
    use BelongsToTenant, HasFactory;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            /*
             * Integer columns are cast because they are compared with === in
             * PHP. MySQL returns them as strings under emulated prepared
             * statements, where "8" === 8 is false — which silently turned an
             * owner into a stranger and a matching id into a mismatch.
             */
            'company_id' => 'integer',
            'voucher_type_id' => 'integer',
            'version' => 'integer',
            'created_by' => 'integer',
            'is_default' => 'boolean',
            'is_active' => 'boolean',
        ];
    }

    public function steps(): HasMany
    {
        return $this->hasMany(WorkflowStep::class)->orderBy('position');
    }

    public function voucherType(): BelongsTo
    {
        return $this->belongsTo(VoucherType::class);
    }

    public function vouchers(): HasMany
    {
        return $this->hasMany(Voucher::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    /** "Employee → HOD → Manager → Completed", as shown in the workflow builder. */
    public function routeSummary(): string
    {
        return $this->steps->pluck('role')
            ->map(fn ($role) => WorkflowStep::roleLabel($role))
            ->implode(' → ');
    }
}
