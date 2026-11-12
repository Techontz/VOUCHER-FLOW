<?php

namespace App\Services\Erp;

use App\Models\Erp\Product;
use App\Models\Erp\StockBalance;
use App\Models\Erp\StockMovement;
use App\Models\Erp\Warehouse;
use App\Models\User;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * The only code that changes a stock balance.
 *
 * Each call writes one ledger row and moves the matching balance in the same
 * transaction, with the balance row locked, so two issues against the last
 * ten cartons cannot both succeed. Inbound stock re-weights the average cost;
 * outbound stock leaves at the average unless the caller names a cost (a
 * reversal takes stock back out at the cost it came in at).
 *
 * Negative stock is refused unless the company's policy allows it.
 */
class StockLedger
{
    public function __construct(private readonly TenantContext $tenant) {}

    /**
     * @param  array{
     *     type: string, reference: string, date?: ?string, reason?: ?string,
     *     batch_number?: ?string, expiry_date?: ?string, unit_cost?: float|string|null,
     *     document_id?: ?int, line_id?: ?int, actor?: ?User
     * }  $context
     */
    public function move(Product $product, Warehouse $warehouse, float $quantity, array $context): StockMovement
    {
        if (! $product->isStocked()) {
            throw new RuntimeException("{$product->name} is a service and holds no stock.");
        }

        if (abs($quantity) < 0.00005) {
            throw new RuntimeException("A movement of {$product->name} needs a quantity.");
        }

        $companyId = $this->tenant->id() ?? throw new RuntimeException('No company is resolved for this stock movement.');
        $batch = (string) ($context['batch_number'] ?? '');

        return DB::transaction(function () use ($product, $warehouse, $quantity, $context, $companyId, $batch) {
            StockBalance::query()->insertOrIgnore([
                'company_id' => $companyId,
                'product_id' => $product->id,
                'warehouse_id' => $warehouse->id,
                'batch_number' => $batch,
                'expiry_date' => $context['expiry_date'] ?? null,
                'quantity' => 0,
                'average_cost' => 0,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            /** @var StockBalance $balance */
            $balance = StockBalance::query()
                ->where(['product_id' => $product->id, 'warehouse_id' => $warehouse->id, 'batch_number' => $batch])
                ->lockForUpdate()
                ->firstOrFail();

            $onHand = (float) $balance->quantity;
            $average = (float) $balance->average_cost;
            $after = round($onHand + $quantity, 4);

            if ($quantity < 0 && $after < 0 && ! BusinessConfig::of($this->tenant->company())->allowsNegativeStock()) {
                $where = $batch !== '' ? "{$warehouse->name}, batch {$batch}" : $warehouse->name;

                throw new RuntimeException(sprintf(
                    'Not enough %s in %s: %s on hand, %s needed.',
                    $product->name, $where, $this->qty($onHand), $this->qty(abs($quantity)),
                ));
            }

            $named = isset($context['unit_cost']) && $context['unit_cost'] !== '' ? (float) $context['unit_cost'] : null;

            if ($quantity > 0) {
                $unitCost = $named ?? ($average > 0 ? $average : (float) $product->cost_price);
                $newAverage = $after > 0 ? (($onHand > 0 ? $onHand * $average : 0) + $quantity * $unitCost) / max($after, 0.0001) : $unitCost;
            } else {
                $unitCost = $named ?? $average;
                // Taking stock out at its own cost leaves the average where it
                // was; at another cost (a reversal) it re-weights what remains.
                $newAverage = ($named !== null && $after > 0)
                    ? max(0, ($onHand * $average + $quantity * $unitCost) / $after)
                    : $average;
            }

            $balance->forceFill([
                'quantity' => $after,
                'average_cost' => round($newAverage, 4),
                'expiry_date' => $balance->expiry_date ?? ($context['expiry_date'] ?? null),
            ])->save();

            $actor = $context['actor'] ?? auth()->user();

            return StockMovement::create([
                'company_id' => $companyId,
                'product_id' => $product->id,
                'warehouse_id' => $warehouse->id,
                'batch_number' => $batch,
                'expiry_date' => $context['expiry_date'] ?? null,
                'type' => $context['type'],
                'quantity' => $quantity,
                'unit_cost' => round($unitCost, 2),
                'value' => round($quantity * $unitCost, 2),
                'balance_after' => $after,
                'stock_document_id' => $context['document_id'] ?? null,
                'stock_document_line_id' => $context['line_id'] ?? null,
                'reference' => $context['reference'],
                'reason' => $context['reason'] ?? null,
                'movement_date' => $context['date'] ?? now()->toDateString(),
                'created_by' => $actor?->id,
                'approved_by' => $actor?->id,
            ]);
        });
    }

    /** What is on hand for a product in one place (every batch), or everywhere. */
    public function onHand(Product $product, ?Warehouse $warehouse = null, ?string $batch = null): float
    {
        return (float) StockBalance::query()
            ->where('product_id', $product->id)
            ->when($warehouse, fn ($q) => $q->where('warehouse_id', $warehouse->id))
            ->when($batch !== null, fn ($q) => $q->where('batch_number', $batch))
            ->sum('quantity');
    }

    private function qty(float $value): string
    {
        return rtrim(rtrim(number_format($value, 4, '.', ','), '0'), '.');
    }
}
