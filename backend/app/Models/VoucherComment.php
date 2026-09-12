<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class VoucherComment extends Model
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
            'voucher_id' => 'integer',
            'company_id' => 'integer',
            'user_id' => 'integer',
        ];
    }

    public function voucher(): BelongsTo
    {
        return $this->belongsTo(Voucher::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
