<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Production & manufacturing.
 *
 *   production_work_centres   lines and machines a bill of materials runs on
 *   production_boms / _lines  what one batch of a finished product consumes,
 *                             versioned, one version active per product
 *   production_orders         a run: planned, released, in progress,
 *                             completed, closed (or cancelled), with its costs
 *   production_receipts       output recorded against an order, waiting for QC
 *   production_qc_checks      the inspection that releases or rejects a receipt
 *
 * Materials and output move through stock documents (source_type
 * 'production_order'), so the stock ledger and the journal stay the only
 * places stock and money change.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('production_work_centres', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('code', 20);
            $table->string('name', 120);
            $table->text('description')->nullable();
            // Output a centre can make per hour, in the finished product's unit.
            $table->decimal('capacity_per_hour', 18, 3)->nullable();
            $table->decimal('hourly_cost', 18, 2)->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['company_id', 'code']);
        });

        Schema::create('production_boms', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->constrained('products')->restrictOnDelete();
            $table->unsignedInteger('version');
            $table->string('name', 160);
            // How many finished units one batch of the components makes.
            $table->decimal('output_quantity', 18, 3);
            $table->foreignId('work_centre_id')->nullable()->constrained('production_work_centres')->nullOnDelete();
            // Conversion cost applied per batch, on top of materials.
            $table->decimal('labour_cost', 18, 2)->default(0);
            $table->decimal('overhead_cost', 18, 2)->default(0);
            $table->boolean('is_active')->default(false);
            $table->text('notes')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('activated_at')->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'product_id', 'version']);
            $table->index(['company_id', 'product_id', 'is_active']);
        });

        Schema::create('production_bom_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('bom_id')->constrained('production_boms')->cascadeOnDelete();
            $table->foreignId('product_id')->constrained('products')->restrictOnDelete();
            // Per batch of the BOM's output quantity.
            $table->decimal('quantity', 18, 4);
            // Allowance for scrap and wastage on top of the quantity, in percent.
            $table->decimal('scrap_percent', 6, 2)->default(0);
            $table->string('note', 255)->nullable();
            $table->unsignedSmallInteger('position')->default(0);
            $table->timestamps();
        });

        Schema::create('production_orders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('product_id')->constrained('products')->restrictOnDelete();
            $table->foreignId('bom_id')->constrained('production_boms')->restrictOnDelete();
            $table->decimal('planned_quantity', 18, 3);
            $table->foreignId('materials_warehouse_id')->constrained('warehouses')->restrictOnDelete();
            $table->foreignId('output_warehouse_id')->constrained('warehouses')->restrictOnDelete();
            $table->date('planned_start');
            $table->date('planned_end');
            // planned · released · in_progress · completed · closed · cancelled
            $table->string('status', 20)->default('planned');
            $table->string('reference', 80)->nullable();
            $table->text('notes')->nullable();

            // Standard cost per finished unit, fixed when the order is released.
            $table->decimal('standard_unit_cost', 18, 4)->nullable();
            // Running totals, kept by the production service as documents post.
            $table->decimal('produced_quantity', 18, 3)->default(0);
            $table->decimal('good_quantity', 18, 3)->default(0);
            $table->decimal('released_quantity', 18, 3)->default(0);
            $table->decimal('rejected_quantity', 18, 3)->default(0);
            $table->decimal('wastage_quantity', 18, 3)->default(0);
            $table->decimal('material_cost', 18, 2)->default(0);
            $table->decimal('conversion_cost', 18, 2)->default(0);
            $table->decimal('received_value', 18, 2)->default(0);
            // Whatever remained on work in progress at close, posted once.
            $table->decimal('variance_value', 18, 2)->nullable();

            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('released_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('released_at')->nullable();
            $table->timestamp('started_at')->nullable();
            $table->foreignId('completed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('completed_at')->nullable();
            $table->foreignId('closed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('closed_at')->nullable();
            $table->foreignId('cancelled_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('cancelled_at')->nullable();
            $table->string('cancel_reason', 255)->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
        });

        Schema::create('production_receipts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('production_order_id')->constrained('production_orders')->cascadeOnDelete();
            $table->string('number', 40);
            $table->date('receipt_date');
            $table->decimal('produced_quantity', 18, 3);
            $table->decimal('good_quantity', 18, 3);
            $table->decimal('rejected_quantity', 18, 3)->default(0);
            $table->decimal('wastage_quantity', 18, 3)->default(0);
            $table->decimal('released_quantity', 18, 3)->default(0);
            $table->string('batch_number', 60)->nullable();
            $table->date('expiry_date')->nullable();
            // The last receipt of the order: it takes the rest of the order's cost.
            $table->boolean('is_final')->default(false);
            // pending_qc · released · rejected
            $table->string('status', 20)->default('pending_qc');
            $table->decimal('conversion_cost', 18, 2)->default(0);
            $table->decimal('unit_cost', 18, 2)->nullable();
            $table->decimal('value', 18, 2)->nullable();
            $table->foreignId('stock_document_id')->nullable()->constrained('stock_documents')->nullOnDelete();
            $table->text('notes')->nullable();
            $table->foreignId('recorded_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
            $table->index(['company_id', 'batch_number']);
        });

        Schema::create('production_qc_checks', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('production_receipt_id')->constrained('production_receipts')->cascadeOnDelete();
            $table->foreignId('production_order_id')->constrained('production_orders')->cascadeOnDelete();
            // release · reject
            $table->string('decision', 20);
            // [{name, target, value, passed}]
            $table->json('parameters');
            $table->text('notes')->nullable();
            $table->foreignId('inspector_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('checked_at');
            $table->timestamps();

            $table->unique('production_receipt_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('production_qc_checks');
        Schema::dropIfExists('production_receipts');
        Schema::dropIfExists('production_orders');
        Schema::dropIfExists('production_bom_lines');
        Schema::dropIfExists('production_boms');
        Schema::dropIfExists('production_work_centres');
    }
};
