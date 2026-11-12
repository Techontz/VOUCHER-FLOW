<?php

namespace App\Models\Erp\Production;

use App\Models\Concerns\BelongsToTenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** The inspection that releases a receipt into stock or rejects it. One per receipt. */
class QcCheck extends Model
{
    use BelongsToTenant;

    public const RELEASE = 'release';

    public const REJECT = 'reject';

    protected $table = 'production_qc_checks';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer',
            'production_receipt_id' => 'integer',
            'production_order_id' => 'integer',
            'parameters' => 'array',
            'checked_at' => 'datetime',
        ];
    }

    public function receipt(): BelongsTo
    {
        return $this->belongsTo(ProductionReceipt::class, 'production_receipt_id');
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(ProductionOrder::class, 'production_order_id');
    }

    public function inspector(): BelongsTo
    {
        return $this->belongsTo(User::class, 'inspector_id');
    }
}
