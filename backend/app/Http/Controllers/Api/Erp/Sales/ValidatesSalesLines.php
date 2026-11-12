<?php

namespace App\Http\Controllers\Api\Erp\Sales;

use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** The line rules a quotation and an order share. */
trait ValidatesSalesLines
{
    /** @param  array<string, mixed>  $extra */
    private function salesDocument(Request $request, int $companyId, array $extra = []): array
    {
        return $request->validate([
            'customer_id' => ['required', 'integer', Rule::exists('customers', 'id')->where('company_id', $companyId)->whereNull('deleted_at')],
            'notes' => ['nullable', 'string', 'max:2000'],
            'lines' => ['required', 'array', 'min:1', 'max:200'],
            'lines.*.product_id' => ['required', 'integer', Rule::exists('products', 'id')->where('company_id', $companyId)->where('is_active', true)],
            'lines.*.quantity' => ['required', 'numeric', 'gt:0', 'max:999999999'],
            'lines.*.unit_price' => ['nullable', 'numeric', 'min:0', 'max:9999999999'],
            'lines.*.discount_percent' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'lines.*.tax_rate' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'lines.*.description' => ['nullable', 'string', 'max:255'],
            ...$extra,
        ]);
    }
}
