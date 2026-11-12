<?php

namespace App\Services\Erp\Sales;

use App\Models\Erp\Customer;
use App\Models\Erp\Product;
use App\Models\Erp\Sales\PriceList;
use App\Models\Erp\Sales\PriceListItem;
use App\Support\Erp\BusinessConfig;
use App\Support\TenantContext;
use RuntimeException;

/**
 * Prices and line arithmetic, in one place so a quotation, an order, an
 * invoice and a credit note can never disagree about a total.
 *
 * Price: the customer's own price list on the date, else the default list,
 * else the product's sale price. Line: quantity × price, less a percentage
 * discount, plus VAT at the line's rate (the company's default unless set),
 * each step rounded to the cent so the journal balances exactly.
 */
class SalesPricing
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function defaultTaxRate(): float
    {
        return (float) (BusinessConfig::of($this->tenant->company())->setting('default_tax_rate') ?? 0);
    }

    /** The list a customer buys from: their own if set and active, else the company default. */
    public function listFor(?Customer $customer): ?PriceList
    {
        if ($customer?->price_list) {
            $own = PriceList::query()->where('code', $customer->price_list)->where('is_active', true)->first();

            if ($own) {
                return $own;
            }
        }

        return PriceList::query()->where('is_default', true)->where('is_active', true)->first();
    }

    /**
     * Unit prices for many products at once.
     *
     * @param  list<int>  $productIds
     * @return array<int, array{price: float, source: string}>
     */
    public function prices(?Customer $customer, array $productIds, ?string $date = null): array
    {
        $date ??= now()->toDateString();
        $list = $this->listFor($customer);
        $products = Product::query()->whereIn('id', $productIds)->get(['id', 'sale_price']);
        $listed = [];

        if ($list) {
            // Latest effective row per product on the date.
            PriceListItem::query()
                ->where('price_list_id', $list->id)
                ->whereIn('product_id', $productIds)
                ->whereDate('effective_from', '<=', $date)
                ->where(fn ($q) => $q->whereNull('effective_to')->orWhereDate('effective_to', '>=', $date))
                ->orderBy('effective_from')
                ->get()
                ->each(function ($item) use (&$listed) {
                    $listed[$item->product_id] = (float) $item->unit_price;
                });
        }

        $out = [];
        foreach ($products as $product) {
            $out[$product->id] = isset($listed[$product->id])
                ? ['price' => $listed[$product->id], 'source' => $list->code]
                : ['price' => (float) $product->sale_price, 'source' => 'product'];
        }

        return $out;
    }

    /**
     * Fills in the price and tax a person left blank and computes the amounts.
     *
     * @param  list<array<string, mixed>>  $lines  each with product_id, quantity, and optional unit_price, discount_percent, tax_rate, description
     * @return list<array<string, mixed>>
     */
    public function priceLines(?Customer $customer, array $lines, ?string $date = null, string $quantityKey = 'quantity'): array
    {
        if (! $lines) {
            throw new RuntimeException('Add at least one line.');
        }

        $ids = array_map(fn ($l) => (int) $l['product_id'], $lines);
        $prices = $this->prices($customer, $ids, $date);
        $tax = $this->defaultTaxRate();
        $priced = [];

        foreach ($lines as $line) {
            $productId = (int) $line['product_id'];

            if (! isset($prices[$productId])) {
                throw new RuntimeException('One of the products is not in this company\'s catalogue.');
            }

            $quantity = (float) ($line[$quantityKey] ?? $line['quantity'] ?? 0);

            if ($quantity <= 0) {
                throw new RuntimeException('Every line needs a quantity greater than zero.');
            }

            $price = isset($line['unit_price']) && $line['unit_price'] !== '' ? (float) $line['unit_price'] : $prices[$productId]['price'];
            $discount = (float) ($line['discount_percent'] ?? 0);
            $rate = isset($line['tax_rate']) && $line['tax_rate'] !== '' ? (float) $line['tax_rate'] : $tax;

            if ($price < 0 || $discount < 0 || $discount > 100 || $rate < 0 || $rate > 100) {
                throw new RuntimeException('Prices cannot be negative, and discount and VAT are percentages from 0 to 100.');
            }

            $priced[] = [
                'product_id' => $productId,
                'description' => $line['description'] ?? null,
                $quantityKey => $quantity,
                ...self::amounts($quantity, $price, $discount, $rate),
            ];
        }

        return $priced;
    }

    /** @return array{unit_price: float, discount_percent: float, tax_rate: float, line_subtotal: float, line_discount: float, line_tax: float, line_total: float} */
    public static function amounts(float $quantity, float $price, float $discountPercent, float $taxRate): array
    {
        $subtotal = round($quantity * $price, 2);
        $discount = round($subtotal * $discountPercent / 100, 2);
        $tax = round(($subtotal - $discount) * $taxRate / 100, 2);

        return [
            'unit_price' => $price,
            'discount_percent' => $discountPercent,
            'tax_rate' => $taxRate,
            'line_subtotal' => $subtotal,
            'line_discount' => $discount,
            'line_tax' => $tax,
            'line_total' => round($subtotal - $discount + $tax, 2),
        ];
    }

    /**
     * @param  iterable<array<string, mixed>|object>  $lines
     * @return array{subtotal: float, discount_total: float, tax_total: float, total: float}
     */
    public static function totals(iterable $lines): array
    {
        $cents = ['subtotal' => 0, 'discount_total' => 0, 'tax_total' => 0, 'total' => 0];

        foreach ($lines as $line) {
            $line = is_array($line) ? $line : $line->toArray();
            $cents['subtotal'] += (int) round((float) $line['line_subtotal'] * 100);
            $cents['discount_total'] += (int) round((float) $line['line_discount'] * 100);
            $cents['tax_total'] += (int) round((float) $line['line_tax'] * 100);
            $cents['total'] += (int) round((float) $line['line_total'] * 100);
        }

        return array_map(fn ($c) => $c / 100, $cents);
    }
}
