<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Finance verification and dispatch: the loading order and everything that
 * happens to it, from the warehouse floor to the customer's signature.
 *
 * Each line keeps four quantities, never one: ordered, approved, loaded and
 * received. Vehicle and driver are kept as text, with nullable ids the fleet
 * module may fill; there is no foreign key, so fleet can ship on its own.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('loading_orders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->foreignId('sales_order_id')->constrained()->restrictOnDelete();
            $table->foreignId('customer_id')->constrained()->restrictOnDelete();
            $table->foreignId('warehouse_id')->constrained()->restrictOnDelete();
            // open · loaded · dispatched · delivered · cancelled
            $table->string('status', 20)->default('open');
            $table->date('planned_date')->nullable();
            $table->string('vehicle_number', 40)->nullable();
            $table->string('driver_name', 120)->nullable();
            $table->unsignedBigInteger('vehicle_id')->nullable();
            $table->unsignedBigInteger('driver_user_id')->nullable();
            $table->string('destination', 255)->nullable();
            $table->text('notes')->nullable();

            // Loading confirmed by the storekeeper: the one moment stock leaves.
            $table->foreignId('stock_document_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('loaded_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('loaded_at')->nullable();
            $table->string('driver_confirmed_name', 120)->nullable();
            $table->foreignId('driver_confirmed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('driver_confirmed_at')->nullable();
            $table->string('security_confirmed_name', 120)->nullable();
            $table->foreignId('security_confirmed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('security_confirmed_at')->nullable();

            $table->string('delivery_note_number', 40)->nullable();
            $table->timestamp('delivery_note_issued_at')->nullable();
            $table->foreignId('delivery_note_issued_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('gate_pass_number', 40)->nullable();
            $table->timestamp('gate_pass_issued_at')->nullable();
            $table->foreignId('gate_pass_issued_by')->nullable()->constrained('users')->nullOnDelete();

            // Proof of delivery.
            $table->string('received_by_name', 120)->nullable();
            $table->date('received_date')->nullable();
            $table->string('delivery_remark', 500)->nullable();
            $table->foreignId('pod_recorded_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('pod_recorded_at')->nullable();

            // A short delivery: open until someone decides return or write-off.
            $table->string('discrepancy_status', 20)->nullable();
            $table->string('discrepancy_note', 500)->nullable();
            $table->foreignId('discrepancy_resolved_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('discrepancy_resolved_at')->nullable();
            $table->foreignId('return_document_id')->nullable()->constrained('stock_documents')->nullOnDelete();

            $table->foreignId('cancelled_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->unique(['company_id', 'delivery_note_number']);
            $table->unique(['company_id', 'gate_pass_number']);
            $table->index(['company_id', 'status']);
        });

        Schema::create('loading_order_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('loading_order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('sales_order_line_id')->constrained()->restrictOnDelete();
            $table->foreignId('product_id')->constrained()->restrictOnDelete();
            $table->decimal('quantity_ordered', 18, 3);
            $table->decimal('quantity_approved', 18, 3);
            $table->decimal('quantity_loaded', 18, 3)->nullable();
            $table->decimal('quantity_received', 18, 3)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('loading_order_lines');
        Schema::dropIfExists('loading_orders');
    }
};
