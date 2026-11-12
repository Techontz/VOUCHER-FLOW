<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The procurement cycle: requisition, request for quotation, purchase order,
 * receipt against it, supplier invoice matched three ways, payment.
 *
 * Receiving goods goes through the core stock documents (a GRN carries
 * source_type 'purchase_order'); the tables here only remember which PO line
 * each receipt and invoice line belongs to, so received and invoiced
 * quantities are facts, not guesses.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('procurement_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->unique()->constrained()->cascadeOnDelete();
            // Requisitions and orders above this total need a second, senior approval.
            $table->decimal('approval_threshold', 18, 2)->default(5000000);
            $table->json('senior_roles')->nullable();
            // How far receipts may exceed the ordered quantity, in percent.
            $table->decimal('receipt_tolerance_percent', 5, 2)->default(0);
            // How far an invoice may differ from the order price or received quantity before it needs approval.
            $table->decimal('price_tolerance_percent', 5, 2)->default(2);
            $table->decimal('quantity_tolerance_percent', 5, 2)->default(0);
            $table->decimal('default_vat_rate', 5, 2)->default(18);
            $table->timestamps();
        });

        Schema::create('purchase_requisitions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('department_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('requested_by')->constrained('users');
            $table->date('needed_by')->nullable();
            $table->text('justification');
            $table->string('status', 20)->default('draft');
            $table->decimal('total', 18, 2)->default(0);
            $table->unsignedTinyInteger('approvals_required')->default(1);
            $table->timestamp('submitted_at')->nullable();
            $table->timestamp('approved_at')->nullable();
            $table->timestamp('rejected_at')->nullable();
            $table->timestamp('cancelled_at')->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
        });

        Schema::create('purchase_requisition_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('purchase_requisition_id')->constrained()->cascadeOnDelete();
            $table->string('line_type', 10)->default('stock');
            $table->foreignId('product_id')->nullable()->constrained();
            $table->string('description', 255);
            $table->decimal('quantity', 18, 3);
            $table->decimal('estimated_unit_price', 18, 2)->default(0);
            $table->decimal('amount', 18, 2)->default(0);
            $table->foreignId('expense_account_id')->nullable()->constrained('accounts');
            $table->timestamps();
        });

        // Who approved or rejected what, at which level, with what comment.
        Schema::create('procurement_approvals', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('approvable_type', 40);
            $table->unsignedBigInteger('approvable_id');
            $table->unsignedTinyInteger('level');
            $table->string('decision', 12);
            $table->foreignId('user_id')->constrained('users');
            $table->string('comment', 500)->nullable();
            $table->timestamps();

            $table->index(['approvable_type', 'approvable_id']);
        });

        Schema::create('purchase_rfqs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('purchase_requisition_id')->nullable()->constrained()->nullOnDelete();
            $table->string('title', 160);
            $table->date('issue_date');
            $table->date('closing_date')->nullable();
            $table->string('status', 20)->default('draft');
            $table->unsignedBigInteger('selected_quotation_id')->nullable();
            $table->string('selection_reason', 500)->nullable();
            $table->foreignId('awarded_by')->nullable()->constrained('users');
            $table->timestamp('awarded_at')->nullable();
            $table->text('notes')->nullable();
            $table->foreignId('created_by')->constrained('users');
            $table->timestamps();

            $table->unique(['company_id', 'number']);
        });

        Schema::create('purchase_rfq_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('purchase_rfq_id')->constrained()->cascadeOnDelete();
            $table->foreignId('purchase_requisition_line_id')->nullable()->constrained()->nullOnDelete();
            $table->string('line_type', 10)->default('stock');
            $table->foreignId('product_id')->nullable()->constrained();
            $table->string('description', 255);
            $table->decimal('quantity', 18, 3);
            $table->foreignId('expense_account_id')->nullable()->constrained('accounts');
            $table->timestamps();
        });

        Schema::create('purchase_rfq_suppliers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('purchase_rfq_id')->constrained()->cascadeOnDelete();
            $table->foreignId('supplier_id')->constrained();
            $table->timestamps();

            $table->unique(['purchase_rfq_id', 'supplier_id']);
        });

        Schema::create('supplier_quotations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('purchase_rfq_id')->constrained()->cascadeOnDelete();
            $table->foreignId('supplier_id')->constrained();
            $table->string('reference', 80)->nullable();
            $table->date('quotation_date');
            $table->date('valid_until')->nullable();
            $table->unsignedInteger('lead_time_days')->nullable();
            $table->string('payment_terms', 160)->nullable();
            $table->string('delivery_terms', 160)->nullable();
            $table->decimal('subtotal', 18, 2)->default(0);
            $table->decimal('vat_amount', 18, 2)->default(0);
            $table->decimal('total', 18, 2)->default(0);
            $table->string('status', 20)->default('received');
            $table->text('notes')->nullable();
            $table->foreignId('created_by')->constrained('users');
            $table->timestamps();

            $table->unique(['purchase_rfq_id', 'supplier_id']);
        });

        Schema::create('supplier_quotation_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('supplier_quotation_id')->constrained()->cascadeOnDelete();
            $table->foreignId('purchase_rfq_line_id')->constrained()->cascadeOnDelete();
            $table->decimal('unit_price', 18, 2);
            $table->decimal('vat_rate', 5, 2)->default(0);
            $table->decimal('amount', 18, 2);
            $table->timestamps();
        });

        Schema::create('purchase_orders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('supplier_id')->constrained();
            $table->foreignId('purchase_requisition_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('supplier_quotation_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('warehouse_id')->nullable()->constrained();
            $table->date('order_date');
            $table->date('expected_date')->nullable();
            $table->string('status', 24)->default('draft');
            $table->string('payment_terms', 160)->nullable();
            $table->string('currency', 3)->default('TZS');
            $table->decimal('subtotal', 18, 2)->default(0);
            $table->decimal('vat_amount', 18, 2)->default(0);
            $table->decimal('total', 18, 2)->default(0);
            $table->unsignedTinyInteger('approvals_required')->default(1);
            $table->text('notes')->nullable();
            $table->string('cancel_reason', 255)->nullable();
            $table->foreignId('created_by')->constrained('users');
            $table->timestamp('submitted_at')->nullable();
            $table->timestamp('approved_at')->nullable();
            $table->timestamp('sent_at')->nullable();
            $table->timestamp('received_at')->nullable();
            $table->timestamp('closed_at')->nullable();
            $table->timestamp('cancelled_at')->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
        });

        Schema::create('purchase_order_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('purchase_order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('purchase_requisition_line_id')->nullable()->constrained()->nullOnDelete();
            $table->string('line_type', 10)->default('stock');
            $table->foreignId('product_id')->nullable()->constrained();
            $table->string('description', 255);
            $table->decimal('quantity', 18, 3);
            $table->decimal('unit_price', 18, 2);
            $table->decimal('vat_rate', 5, 2)->default(0);
            $table->decimal('amount', 18, 2);
            $table->decimal('vat_amount', 18, 2)->default(0);
            $table->decimal('received_quantity', 18, 3)->default(0);
            $table->decimal('invoiced_quantity', 18, 3)->default(0);
            $table->foreignId('expense_account_id')->nullable()->constrained('accounts');
            $table->timestamps();
        });

        // One row per delivery (a posted GRN) or service confirmation.
        Schema::create('purchase_receipts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('purchase_order_id')->constrained()->cascadeOnDelete();
            $table->string('kind', 10);
            $table->string('number', 40);
            $table->foreignId('stock_document_id')->nullable()->unique()->constrained()->nullOnDelete();
            $table->date('received_date');
            $table->string('delivery_note', 80)->nullable();
            $table->decimal('value', 18, 2)->default(0);
            $table->text('notes')->nullable();
            $table->foreignId('received_by')->constrained('users');
            $table->timestamps();

            $table->unique(['company_id', 'number']);
        });

        Schema::create('purchase_receipt_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('purchase_receipt_id')->constrained()->cascadeOnDelete();
            $table->foreignId('purchase_order_line_id')->constrained()->cascadeOnDelete();
            $table->foreignId('stock_document_line_id')->nullable()->constrained()->nullOnDelete();
            $table->decimal('quantity', 18, 3);
            $table->decimal('unit_cost', 18, 2);
            $table->decimal('value', 18, 2);
            $table->timestamps();
        });

        Schema::create('supplier_invoices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('supplier_id')->constrained();
            $table->foreignId('purchase_order_id')->constrained();
            $table->string('supplier_invoice_number', 80);
            $table->date('invoice_date');
            $table->date('due_date');
            $table->decimal('subtotal', 18, 2)->default(0);
            $table->decimal('vat_amount', 18, 2)->default(0);
            $table->decimal('total', 18, 2)->default(0);
            $table->decimal('amount_paid', 18, 2)->default(0);
            $table->string('status', 24)->default('draft');
            $table->string('match_status', 16)->default('matched');
            $table->foreignId('variance_approved_by')->nullable()->constrained('users');
            $table->timestamp('variance_approved_at')->nullable();
            $table->foreignId('posted_by')->nullable()->constrained('users');
            $table->timestamp('posted_at')->nullable();
            $table->foreignId('journal_entry_id')->nullable()->constrained()->nullOnDelete();
            $table->text('notes')->nullable();
            $table->foreignId('created_by')->constrained('users');
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            // A supplier's invoice number is entered once, ever.
            $table->unique(['company_id', 'supplier_id', 'supplier_invoice_number'], 'supplier_invoices_supplier_number_unique');
            $table->index(['company_id', 'status']);
        });

        Schema::create('supplier_invoice_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('supplier_invoice_id')->constrained()->cascadeOnDelete();
            $table->foreignId('purchase_order_line_id')->constrained();
            $table->string('line_type', 10);
            $table->string('description', 255);
            $table->decimal('quantity', 18, 3);
            $table->decimal('unit_price', 18, 2);
            $table->decimal('vat_rate', 5, 2)->default(0);
            $table->decimal('amount', 18, 2);
            $table->decimal('vat_amount', 18, 2)->default(0);
            // The match, as computed when the line was entered: what the order
            // said, what was received and not yet invoiced, and the differences.
            $table->decimal('order_unit_price', 18, 2);
            $table->decimal('matchable_quantity', 18, 3);
            $table->decimal('price_variance', 18, 2)->default(0);
            $table->decimal('quantity_variance', 18, 3)->default(0);
            $table->boolean('flagged')->default(false);
            $table->foreignId('expense_account_id')->nullable()->constrained('accounts');
            $table->timestamps();
        });

        Schema::create('supplier_payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('supplier_id')->constrained();
            $table->foreignId('account_id')->constrained('accounts');
            $table->date('payment_date');
            $table->string('method', 30)->default('bank_transfer');
            $table->string('reference', 80)->nullable();
            $table->decimal('amount', 18, 2);
            $table->string('status', 20)->default('draft');
            $table->text('notes')->nullable();
            $table->foreignId('created_by')->constrained('users');
            $table->foreignId('posted_by')->nullable()->constrained('users');
            $table->timestamp('posted_at')->nullable();
            $table->foreignId('journal_entry_id')->nullable()->constrained()->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
        });

        Schema::create('supplier_payment_allocations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('supplier_payment_id')->constrained()->cascadeOnDelete();
            $table->foreignId('supplier_invoice_id')->constrained();
            $table->decimal('amount', 18, 2);
            $table->timestamps();

            $table->unique(['supplier_payment_id', 'supplier_invoice_id'], 'supplier_payment_alloc_unique');
        });
    }

    public function down(): void
    {
        foreach ([
            'supplier_payment_allocations', 'supplier_payments', 'supplier_invoice_lines', 'supplier_invoices',
            'purchase_receipt_lines', 'purchase_receipts', 'purchase_order_lines', 'purchase_orders',
            'supplier_quotation_lines', 'supplier_quotations', 'purchase_rfq_suppliers', 'purchase_rfq_lines',
            'purchase_rfqs', 'procurement_approvals', 'purchase_requisition_lines', 'purchase_requisitions',
            'procurement_settings',
        ] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
