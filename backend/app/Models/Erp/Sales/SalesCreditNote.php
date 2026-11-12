<?php

namespace App\Models\Erp\Sales;

use App\Models\Concerns\BelongsToTenant;
use App\Models\Erp\Customer;
use App\Models\Erp\StockDocument;
use App\Models\Erp\Warehouse;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Takes back part of an invoice: Dr Sales returns and Dr VAT payable,
 * Cr Accounts receivable. A return also brings the goods back to stock.
 */
class SalesCreditNote extends Model
{
    use BelongsToTenant;

    public const STATUS_DRAFT = 'draft';

    public const STATUS_POSTED = 'posted';

    public const STATUS_CANCELLED = 'cancelled';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'company_id' => 'integer', 'customer_id' => 'integer', 'sales_invoice_id' => 'integer',
            'warehouse_id' => 'integer', 'stock_document_id' => 'integer',
            'credit_date' => 'date', 'posted_at' => 'datetime', 'return_to_stock' => 'boolean',
            'subtotal' => 'decimal:2', 'discount_total' => 'decimal:2', 'tax_total' => 'decimal:2', 'total' => 'decimal:2',
        ];
    }

    public function lines(): HasMany
    {
        return $this->hasMany(SalesCreditNoteLine::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class)->withTrashed();
    }

    public function invoice(): BelongsTo
    {
        return $this->belongsTo(SalesInvoice::class, 'sales_invoice_id');
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class);
    }

    public function stockDocument(): BelongsTo
    {
        return $this->belongsTo(StockDocument::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function poster(): BelongsTo
    {
        return $this->belongsTo(User::class, 'posted_by');
    }
}
