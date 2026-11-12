<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Sales: price lists, quotations, orders, invoices, receipts and credit notes.
 *
 * Money is decimal(18,2), quantities decimal(18,3). An order line keeps the
 * quantity ordered, the quantity approved, and the running totals loaded,
 * received and invoiced as separate columns, so no figure overwrites another.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('price_lists', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            // customers.price_list stores this code.
            $table->string('code', 40);
            $table->string('name', 120);
            $table->boolean('is_default')->default(false);
            $table->boolean('is_active')->default(true);
            $table->string('notes', 255)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'code']);
        });

        Schema::create('price_list_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('price_list_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->constrained()->cascadeOnDelete();
            $table->decimal('unit_price', 18, 2);
            $table->date('effective_from');
            $table->date('effective_to')->nullable();
            $table->timestamps();

            $table->unique(['price_list_id', 'product_id', 'effective_from']);
            $table->index(['company_id', 'product_id']);
        });

        Schema::create('sales_quotations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('customer_id')->constrained()->restrictOnDelete();
            $table->date('quote_date');
            $table->date('valid_until')->nullable();
            // draft · sent · converted · rejected · cancelled
            $table->string('status', 20)->default('draft');
            $table->decimal('subtotal', 18, 2)->default(0);
            $table->decimal('discount_total', 18, 2)->default(0);
            $table->decimal('tax_total', 18, 2)->default(0);
            $table->decimal('total', 18, 2)->default(0);
            $table->text('notes')->nullable();
            $table->unsignedBigInteger('sales_order_id')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
        });

        Schema::create('sales_orders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('customer_id')->constrained()->restrictOnDelete();
            $table->foreignId('quotation_id')->nullable()->constrained('sales_quotations')->nullOnDelete();
            $table->foreignId('warehouse_id')->nullable()->constrained()->nullOnDelete();
            $table->date('order_date');
            $table->date('required_date')->nullable();
            // draft · submitted · awaiting_payment · ready · loading · dispatched · delivered · rejected · cancelled
            $table->string('status', 20)->default('draft');
            // prepayment · credit, fixed from the customer's terms at approval
            $table->string('payment_mode', 20)->nullable();
            $table->decimal('subtotal', 18, 2)->default(0);
            $table->decimal('discount_total', 18, 2)->default(0);
            $table->decimal('tax_total', 18, 2)->default(0);
            $table->decimal('total', 18, 2)->default(0);
            $table->string('delivery_address', 255)->nullable();
            $table->text('notes')->nullable();
            // What the credit policy said at approval, and any override.
            $table->json('policy_check')->nullable();
            $table->string('override_reason', 500)->nullable();
            $table->foreignId('overridden_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('submitted_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('submitted_at')->nullable();
            $table->foreignId('approved_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('approved_at')->nullable();
            $table->timestamp('payment_verified_at')->nullable();
            $table->string('rejection_reason', 500)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
            $table->index(['company_id', 'customer_id']);
        });

        foreach (['sales_quotation_lines' => 'sales_quotations', 'sales_order_lines' => 'sales_orders'] as $name => $parent) {
            Schema::create($name, function (Blueprint $table) use ($name, $parent) {
                $table->id();
                $table->foreignId($name === 'sales_quotation_lines' ? 'quotation_id' : 'sales_order_id')->constrained($parent)->cascadeOnDelete();
                $table->foreignId('product_id')->constrained()->restrictOnDelete();
                $table->string('description', 255)->nullable();
                if ($name === 'sales_order_lines') {
                    $table->decimal('quantity_ordered', 18, 3);
                    $table->decimal('quantity_approved', 18, 3)->nullable();
                    $table->decimal('quantity_loaded', 18, 3)->default(0);
                    $table->decimal('quantity_received', 18, 3)->default(0);
                    $table->decimal('quantity_invoiced', 18, 3)->default(0);
                } else {
                    $table->decimal('quantity', 18, 3);
                }
                $table->decimal('unit_price', 18, 2);
                $table->decimal('discount_percent', 5, 2)->default(0);
                $table->decimal('tax_rate', 5, 2)->default(0);
                $table->decimal('line_subtotal', 18, 2)->default(0);
                $table->decimal('line_discount', 18, 2)->default(0);
                $table->decimal('line_tax', 18, 2)->default(0);
                $table->decimal('line_total', 18, 2)->default(0);
                $table->timestamps();
            });
        }

        Schema::create('sales_invoices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('customer_id')->constrained()->restrictOnDelete();
            $table->foreignId('sales_order_id')->nullable()->constrained()->nullOnDelete();
            // Set when the invoice bills what one loading order delivered.
            $table->unsignedBigInteger('loading_order_id')->nullable();
            $table->date('invoice_date');
            $table->date('due_date');
            // draft · posted · cancelled
            $table->string('status', 20)->default('draft');
            $table->decimal('subtotal', 18, 2)->default(0);
            $table->decimal('discount_total', 18, 2)->default(0);
            $table->decimal('tax_total', 18, 2)->default(0);
            $table->decimal('total', 18, 2)->default(0);
            $table->decimal('amount_paid', 18, 2)->default(0);
            $table->decimal('amount_credited', 18, 2)->default(0);
            $table->text('notes')->nullable();
            $table->foreignId('posted_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('posted_at')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'customer_id', 'status']);
        });

        Schema::create('sales_invoice_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('sales_invoice_id')->constrained()->cascadeOnDelete();
            $table->foreignId('sales_order_line_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('product_id')->constrained()->restrictOnDelete();
            $table->string('description', 255)->nullable();
            $table->decimal('quantity', 18, 3);
            $table->decimal('quantity_credited', 18, 3)->default(0);
            $table->decimal('unit_price', 18, 2);
            $table->decimal('discount_percent', 5, 2)->default(0);
            $table->decimal('tax_rate', 5, 2)->default(0);
            $table->decimal('line_subtotal', 18, 2)->default(0);
            $table->decimal('line_discount', 18, 2)->default(0);
            $table->decimal('line_tax', 18, 2)->default(0);
            $table->decimal('line_total', 18, 2)->default(0);
            $table->timestamps();
        });

        Schema::create('sales_receipts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('customer_id')->constrained()->restrictOnDelete();
            // A cash or bank account: type asset, code 1100 to 1299.
            $table->foreignId('account_id')->constrained()->restrictOnDelete();
            $table->date('receipt_date');
            $table->decimal('amount', 18, 2);
            // cash · bank_transfer · mobile_money · cheque
            $table->string('method', 20)->default('bank_transfer');
            $table->string('reference', 80)->nullable();
            // recorded · verified · rejected
            $table->string('status', 20)->default('recorded');
            $table->text('notes')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('verified_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('verified_at')->nullable();
            $table->string('rejection_reason', 500)->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
        });

        Schema::create('sales_receipt_allocations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('sales_receipt_id')->constrained()->cascadeOnDelete();
            $table->foreignId('sales_invoice_id')->constrained()->restrictOnDelete();
            $table->decimal('amount', 18, 2);
            $table->timestamps();

            $table->unique(['sales_receipt_id', 'sales_invoice_id'], 'sales_receipt_alloc_unique');
        });

        Schema::create('sales_credit_notes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('customer_id')->constrained()->restrictOnDelete();
            $table->foreignId('sales_invoice_id')->constrained()->restrictOnDelete();
            $table->date('credit_date');
            $table->string('reason', 255);
            // draft · posted · cancelled
            $table->string('status', 20)->default('draft');
            // Whether goods come back to stock (a return) or only money is credited.
            $table->boolean('return_to_stock')->default(false);
            $table->foreignId('warehouse_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('stock_document_id')->nullable()->constrained()->nullOnDelete();
            $table->decimal('subtotal', 18, 2)->default(0);
            $table->decimal('discount_total', 18, 2)->default(0);
            $table->decimal('tax_total', 18, 2)->default(0);
            $table->decimal('total', 18, 2)->default(0);
            $table->foreignId('posted_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('posted_at')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
        });

        Schema::create('sales_credit_note_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('sales_credit_note_id')->constrained()->cascadeOnDelete();
            $table->foreignId('sales_invoice_line_id')->constrained()->restrictOnDelete();
            $table->foreignId('product_id')->constrained()->restrictOnDelete();
            $table->decimal('quantity', 18, 3);
            $table->decimal('unit_price', 18, 2);
            $table->decimal('discount_percent', 5, 2)->default(0);
            $table->decimal('tax_rate', 5, 2)->default(0);
            $table->decimal('line_subtotal', 18, 2)->default(0);
            $table->decimal('line_discount', 18, 2)->default(0);
            $table->decimal('line_tax', 18, 2)->default(0);
            $table->decimal('line_total', 18, 2)->default(0);
            $table->string('batch_number', 60)->nullable();
            $table->date('expiry_date')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        foreach ([
            'sales_credit_note_lines', 'sales_credit_notes', 'sales_receipt_allocations', 'sales_receipts',
            'sales_invoice_lines', 'sales_invoices', 'sales_order_lines', 'sales_orders',
            'sales_quotation_lines', 'sales_quotations', 'price_list_items', 'price_lists',
        ] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
