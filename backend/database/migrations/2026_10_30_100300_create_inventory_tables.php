<?php

use App\Services\Erp\StockLedger;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Inventory & warehouses.
 *
 * Three layers, each with one job:
 *   stock_documents / lines  what a person asked for (a GRN, a transfer …)
 *   stock_movements          the append-only ledger a posted document writes
 *   stock_balances           the running total per product, place and batch
 *
 * A balance is never written by hand. {@see StockLedger} is
 * the only code that touches it, always alongside the movement that explains
 * the change, inside one transaction with the balance row locked.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('units', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('code', 20);
            $table->string('name', 60);
            // Whether quantities may be fractional (litre, kg) or whole (piece).
            $table->boolean('allows_decimals')->default(false);
            $table->timestamps();

            $table->unique(['company_id', 'code']);
        });

        Schema::create('product_categories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('name', 120);
            $table->foreignId('parent_id')->nullable()->constrained('product_categories')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'name']);
        });

        Schema::create('warehouses', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('code', 20);
            $table->string('name', 120);
            // warehouse · depot · shop · branch · production
            $table->string('type', 20)->default('warehouse');
            $table->string('branch', 120)->nullable();
            $table->string('location', 255)->nullable();
            $table->foreignId('manager_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['company_id', 'code']);
        });

        Schema::create('products', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('sku', 60);
            $table->string('barcode', 80)->nullable();
            $table->string('name', 180);
            $table->string('brand', 80)->nullable();
            // stock · service · raw_material · finished_good · packaging
            $table->string('type', 20)->default('stock');
            $table->foreignId('category_id')->nullable()->constrained('product_categories')->nullOnDelete();
            $table->foreignId('unit_id')->constrained('units')->restrictOnDelete();
            $table->decimal('cost_price', 18, 2)->default(0);
            $table->decimal('sale_price', 18, 2)->default(0);
            $table->decimal('reorder_level', 18, 4)->default(0);
            $table->boolean('track_batches')->default(false);
            $table->boolean('track_expiry')->default(false);
            $table->boolean('track_serials')->default(false);
            $table->json('custom_fields')->nullable();
            $table->boolean('is_active')->default(true);
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
            $table->softDeletes();

            $table->unique(['company_id', 'sku']);
            $table->index(['company_id', 'barcode']);
            $table->index(['company_id', 'name']);
        });

        Schema::create('stock_documents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            // opening · grn · issue · transfer · adjustment · count
            $table->string('type', 20);
            $table->string('number', 40);
            $table->date('document_date');
            $table->string('status', 20)->default('draft');
            $table->foreignId('warehouse_id')->constrained()->restrictOnDelete();
            $table->foreignId('to_warehouse_id')->nullable()->constrained('warehouses')->restrictOnDelete();
            $table->foreignId('supplier_id')->nullable()->constrained()->nullOnDelete();
            $table->string('reference', 80)->nullable();
            $table->string('reason', 255)->nullable();
            $table->text('notes')->nullable();
            $table->foreignId('reversal_of_id')->nullable()->constrained('stock_documents')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('posted_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('posted_at')->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'type', 'status']);
        });

        Schema::create('stock_document_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('stock_document_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->constrained()->restrictOnDelete();
            // For a count this is the counted quantity; for an adjustment it is
            // signed (+ found, − lost); everywhere else it is positive.
            $table->decimal('quantity', 18, 4);
            $table->decimal('unit_cost', 18, 2)->nullable();
            $table->string('batch_number', 60)->nullable();
            $table->date('expiry_date')->nullable();
            $table->string('serial_number', 80)->nullable();
            // A count records what the system thought it had, at posting.
            $table->decimal('system_quantity', 18, 4)->nullable();
            $table->string('note', 255)->nullable();
            $table->timestamps();
        });

        Schema::create('stock_movements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->constrained()->restrictOnDelete();
            $table->foreignId('warehouse_id')->constrained()->restrictOnDelete();
            $table->string('batch_number', 60)->default('');
            $table->date('expiry_date')->nullable();
            // opening · grn · issue · transfer_in · transfer_out · adjustment · count · reversal
            $table->string('type', 20);
            $table->decimal('quantity', 18, 4);
            $table->decimal('unit_cost', 18, 2);
            $table->decimal('value', 18, 2);
            $table->decimal('balance_after', 18, 4);
            $table->foreignId('stock_document_id')->nullable()->constrained()->restrictOnDelete();
            $table->foreignId('stock_document_line_id')->nullable()->constrained()->restrictOnDelete();
            $table->string('reference', 40);
            $table->string('reason', 255)->nullable();
            $table->date('movement_date');
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('approved_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('created_at')->useCurrent();

            // One ledger row per document line, type and place (a transfer line
            // writes one out and one in): posting the same line twice is
            // refused by the database, not only by the code.
            $table->unique(['stock_document_line_id', 'type', 'warehouse_id'], 'movement_line_unique');
            $table->index(['company_id', 'product_id', 'warehouse_id']);
            $table->index(['company_id', 'movement_date']);
        });

        Schema::create('stock_balances', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->constrained()->cascadeOnDelete();
            $table->foreignId('warehouse_id')->constrained()->cascadeOnDelete();
            $table->string('batch_number', 60)->default('');
            $table->date('expiry_date')->nullable();
            $table->decimal('quantity', 18, 4)->default(0);
            // Weighted average cost of what is on hand.
            $table->decimal('average_cost', 18, 4)->default(0);
            $table->timestamps();

            $table->unique(['company_id', 'product_id', 'warehouse_id', 'batch_number'], 'stock_balance_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_balances');
        Schema::dropIfExists('stock_movements');
        Schema::dropIfExists('stock_document_lines');
        Schema::dropIfExists('stock_documents');
        Schema::dropIfExists('products');
        Schema::dropIfExists('warehouses');
        Schema::dropIfExists('product_categories');
        Schema::dropIfExists('units');
    }
};
