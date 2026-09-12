<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class VoucherType extends Model
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
            'sort_order' => 'integer',
            'is_active' => 'boolean',
            'reset_yearly' => 'boolean',

            // Cast, because these are compared numerically and MySQL returns
            // integer columns as strings under emulated prepared statements.
            // Without this the year check in VoucherNumberGenerator was a
            // string-versus-int comparison that was true every time.
            'next_number' => 'integer',
            'current_year' => 'integer',
            'seq_padding' => 'integer',
        ];
    }

    public function vouchers(): HasMany
    {
        return $this->hasMany(Voucher::class);
    }

    public function workflows(): HasMany
    {
        return $this->hasMany(Workflow::class);
    }

    public function label(string $locale = 'en'): string
    {
        return $locale === 'sw' && $this->name_sw ? $this->name_sw : $this->name;
    }
}
