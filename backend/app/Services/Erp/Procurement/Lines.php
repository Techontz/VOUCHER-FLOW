<?php

namespace App\Services\Erp\Procurement;

use App\Models\Erp\Account;
use App\Models\Erp\Procurement\PurchaseRequisitionLine;
use App\Models\Erp\Product;
use RuntimeException;

/**
 * What a procurement line must say before it is stored: a stock line names a
 * product the company holds in stock, a service line (repairs, rent,
 * insurance) names no product and describes the service instead.
 */
class Lines
{
    /**
     * @param  array<string, mixed>  $line
     * @return array{line_type: string, product_id: ?int, description: string, expense_account_id: ?int}
     */
    public static function normalise(array $line, int $index): array
    {
        $type = $line['line_type'] ?? PurchaseRequisitionLine::TYPE_STOCK;
        $n = $index + 1;

        if ($type === PurchaseRequisitionLine::TYPE_SERVICE) {
            $description = trim((string) ($line['description'] ?? ''));

            if ($description === '') {
                throw new RuntimeException("Line {$n}: describe the service being bought.");
            }

            $account = null;
            if (! empty($line['expense_account_id'])) {
                $account = Account::query()->whereKey($line['expense_account_id'])->where('type', 'expense')->where('is_active', true)->first()
                    ?? throw new RuntimeException("Line {$n}: choose an active expense account.");
            }

            return ['line_type' => $type, 'product_id' => null, 'description' => mb_substr($description, 0, 255), 'expense_account_id' => $account?->id];
        }

        $product = Product::query()->find($line['product_id'] ?? 0)
            ?? throw new RuntimeException("Line {$n}: choose a product from this company's catalogue.");

        if (! $product->isStocked()) {
            throw new RuntimeException("Line {$n}: {$product->name} is a service; add it as a service line.");
        }

        if (! $product->is_active) {
            throw new RuntimeException("Line {$n}: {$product->name} is inactive.");
        }

        $description = trim((string) ($line['description'] ?? '')) ?: $product->name;

        return ['line_type' => PurchaseRequisitionLine::TYPE_STOCK, 'product_id' => $product->id, 'description' => mb_substr($description, 0, 255), 'expense_account_id' => null];
    }

    /** A requisition line id, kept only when it belongs to the requisition the document came from. */
    public static function requisitionLine(?int $requisitionId, mixed $lineId): ?int
    {
        if (! $requisitionId || ! $lineId) {
            return null;
        }

        return PurchaseRequisitionLine::query()->whereKey($lineId)->where('purchase_requisition_id', $requisitionId)->value('id');
    }

    public static function money(float $value): float
    {
        return round($value, 2);
    }
}
