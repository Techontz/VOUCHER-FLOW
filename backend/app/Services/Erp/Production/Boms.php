<?php

namespace App\Services\Erp\Production;

use App\Models\Erp\Product;
use App\Models\Erp\Production\Bom;
use App\Models\Erp\StockBalance;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Bills of materials and their versions.
 *
 * A version that an order has used is history: it can no longer be edited or
 * deleted, so a change becomes a new version. Activating a version
 * deactivates the product's others in the same transaction, so a product
 * never has two active recipes.
 */
class Boms
{
    public function __construct(private readonly AuditLogger $audit) {}

    /**
     * @param  array<string, mixed>  $data
     * @param  list<array<string, mixed>>  $lines
     */
    public function create(array $data, array $lines, User $actor): Bom
    {
        return DB::transaction(function () use ($data, $lines, $actor) {
            $product = $this->finishedProduct((int) $data['product_id']);

            $version = (int) Bom::query()->where('product_id', $product->id)->lockForUpdate()->max('version') + 1;
            $first = $version === 1;

            $bom = Bom::create([
                ...$this->header($data),
                'product_id' => $product->id,
                'version' => $version,
                'name' => $data['name'] ?? "{$product->name} v{$version}",
                // The first recipe of a product is the one in use.
                'is_active' => $first,
                'activated_at' => $first ? now() : null,
                'created_by' => $actor->id,
            ]);

            $this->writeLines($bom, $lines);
            $this->audit->log('production.bom.created', "Created bill of materials {$bom->name} (version {$bom->version})", $bom, actor: $actor);

            return $bom->load('lines.product.unit', 'product.unit', 'workCentre');
        });
    }

    /**
     * @param  array<string, mixed>  $data
     * @param  list<array<string, mixed>>  $lines
     */
    public function update(Bom $bom, array $data, array $lines, User $actor): Bom
    {
        return DB::transaction(function () use ($bom, $data, $lines, $actor) {
            $locked = Bom::query()->whereKey($bom->id)->lockForUpdate()->firstOrFail();
            $this->assertUnused($locked, 'edited');

            $locked->update([...$this->header($data), 'name' => $data['name'] ?? $locked->name]);
            $locked->lines()->delete();
            $this->writeLines($locked, $lines);

            $this->audit->log('production.bom.updated', "Edited bill of materials {$locked->name} (version {$locked->version})", $locked, actor: $actor);

            return $locked->load('lines.product.unit', 'product.unit', 'workCentre');
        });
    }

    /** Copies a version into a new, inactive one that can be edited freely. */
    public function newVersion(Bom $bom, User $actor): Bom
    {
        $bom->loadMissing('lines');

        $copy = $this->create([
            ...$bom->only(['product_id', 'output_quantity', 'work_centre_id', 'labour_cost', 'overhead_cost', 'notes']),
            'name' => null,
        ], $bom->lines->map(fn ($l) => $l->only(['product_id', 'quantity', 'scrap_percent', 'note']))->all(), $actor);

        $copy->update(['name' => preg_replace('/ v\d+$/', '', $bom->name)." v{$copy->version}"]);

        return $copy;
    }

    public function activate(Bom $bom, User $actor): Bom
    {
        return DB::transaction(function () use ($bom, $actor) {
            Bom::query()->where('product_id', $bom->product_id)->lockForUpdate()->get();

            if (! $bom->lines()->exists()) {
                throw new RuntimeException('A bill of materials needs at least one component before it can be used.');
            }

            Bom::query()->where('product_id', $bom->product_id)->whereKeyNot($bom->id)->update(['is_active' => false]);
            $bom->update(['is_active' => true, 'activated_at' => now()]);

            $this->audit->log('production.bom.activated', "Activated version {$bom->version} of {$bom->name}", $bom, actor: $actor);

            return $bom->fresh(['lines.product.unit', 'product.unit', 'workCentre']);
        });
    }

    public function delete(Bom $bom, User $actor): void
    {
        DB::transaction(function () use ($bom, $actor) {
            $locked = Bom::query()->whereKey($bom->id)->lockForUpdate()->firstOrFail();
            $this->assertUnused($locked, 'deleted');

            if ($locked->is_active && Bom::query()->where('product_id', $locked->product_id)->count() > 1) {
                throw new RuntimeException('Activate another version before deleting the one in use.');
            }

            $this->audit->log('production.bom.deleted', "Deleted bill of materials {$locked->name} (version {$locked->version})", $locked, actor: $actor);
            $locked->delete();
        });
    }

    /**
     * Standard cost of one finished unit: each component at its current
     * average cost (or list cost when none is held), with its scrap
     * allowance, plus labour and overhead.
     *
     * @return array{materials: float, conversion: float, unit_cost: float, lines: list<array<string, mixed>>}
     */
    public function standardCost(Bom $bom): array
    {
        $bom->loadMissing('lines.product');
        $output = max((float) $bom->output_quantity, 0.0001);
        $costs = $this->averageCosts($bom->lines->pluck('product_id')->all());
        $lines = [];
        $materials = 0.0;

        foreach ($bom->lines as $line) {
            $perUnit = (float) $line->quantity / $output * (1 + (float) $line->scrap_percent / 100);
            $unitCost = $costs[$line->product_id] ?? (float) $line->product->cost_price;
            $materials += $perUnit * $unitCost;
            $lines[] = ['product_id' => $line->product_id, 'per_unit' => round($perUnit, 6), 'unit_cost' => round($unitCost, 4), 'cost_per_unit' => round($perUnit * $unitCost, 4)];
        }

        $conversion = $bom->conversionPerUnit();

        return [
            'materials' => round($materials, 4),
            'conversion' => round($conversion, 4),
            'unit_cost' => round($materials + $conversion, 4),
            'lines' => $lines,
        ];
    }

    /**
     * Weighted average cost across every place and batch each product is held.
     *
     * @param  list<int>  $productIds
     * @return array<int, float>
     */
    public function averageCosts(array $productIds): array
    {
        if (! $productIds) {
            return [];
        }

        return StockBalance::query()
            ->whereIn('product_id', $productIds)
            ->where('quantity', '>', 0)
            ->groupBy('product_id')
            ->selectRaw('product_id, SUM(quantity * average_cost) / SUM(quantity) as cost')
            ->pluck('cost', 'product_id')
            ->map(fn ($c) => (float) $c)
            ->all();
    }

    private function finishedProduct(int $id): Product
    {
        $product = Product::query()->find($id) ?? throw new RuntimeException('That product is not in this company\'s catalogue.');

        if ($product->type !== 'finished_good') {
            throw new RuntimeException("{$product->name} is not a finished good. Bills of materials are for products of type finished good.");
        }

        return $product;
    }

    /** @return array<string, mixed> */
    private function header(array $data): array
    {
        if ((float) ($data['output_quantity'] ?? 0) <= 0) {
            throw new RuntimeException('The output quantity must be greater than zero.');
        }

        return [
            'output_quantity' => $data['output_quantity'],
            'work_centre_id' => $data['work_centre_id'] ?? null,
            'labour_cost' => $data['labour_cost'] ?? 0,
            'overhead_cost' => $data['overhead_cost'] ?? 0,
            'notes' => $data['notes'] ?? null,
        ];
    }

    /** @param  list<array<string, mixed>>  $lines */
    private function writeLines(Bom $bom, array $lines): void
    {
        if (! $lines) {
            throw new RuntimeException('Add at least one component.');
        }

        $ids = array_map(fn ($l) => (int) $l['product_id'], $lines);

        if (count($ids) !== count(array_unique($ids))) {
            throw new RuntimeException('Each component may appear only once; add the quantities together.');
        }

        $products = Product::query()->whereIn('id', $ids)->get()->keyBy('id');

        foreach ($lines as $position => $line) {
            $product = $products[(int) $line['product_id']] ?? throw new RuntimeException('One of the components is not in this company\'s catalogue.');

            if ($product->id === $bom->product_id) {
                throw new RuntimeException("{$product->name} cannot be a component of itself.");
            }

            if (! $product->isStocked()) {
                throw new RuntimeException("{$product->name} is a service and cannot be a component.");
            }

            if ((float) $line['quantity'] <= 0) {
                throw new RuntimeException("{$product->name}: the quantity per batch must be greater than zero.");
            }

            $bom->lines()->create([
                'product_id' => $product->id,
                'quantity' => $line['quantity'],
                'scrap_percent' => $line['scrap_percent'] ?? 0,
                'note' => $line['note'] ?? null,
                'position' => $position,
            ]);
        }
    }

    private function assertUnused(Bom $bom, string $verb): void
    {
        if ($bom->orders()->exists()) {
            throw new RuntimeException("Version {$bom->version} of {$bom->name} has been used by production orders and cannot be {$verb}. Create a new version instead.");
        }
    }
}
