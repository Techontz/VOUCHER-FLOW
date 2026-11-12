<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Trips and what they cost: fuel issued, expenses and allowances, and the
 * share of each vehicle's fixed costs a trip absorbs.
 *
 * fleet_cost_allocations is the single place a fixed cost meets a trip. One
 * row per trip per month, so a trip absorbs a month's fixed cost once, and the
 * service refuses to allocate more of a month than the vehicle costs in it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fleet_trips', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 30);
            // customer_vehicle | charged | included | hired
            $table->string('cost_option', 20);
            $table->foreignId('vehicle_id')->nullable()->constrained('fleet_vehicles')->restrictOnDelete();
            $table->foreignId('driver_id')->nullable()->constrained('fleet_drivers')->restrictOnDelete();
            // The customer's own truck, when the customer collects.
            $table->string('external_vehicle', 60)->nullable();
            $table->foreignId('customer_id')->nullable()->constrained('customers')->nullOnDelete();
            $table->string('origin', 80);
            $table->string('destination', 80);
            $table->decimal('distance_km', 18, 1)->default(0);
            $table->dateTime('planned_start');
            $table->dateTime('planned_end')->nullable();
            $table->dateTime('actual_start')->nullable();
            $table->dateTime('actual_end')->nullable();
            $table->decimal('odometer_out', 18, 1)->nullable();
            $table->decimal('odometer_in', 18, 1)->nullable();
            // A business document from another module, by reference only.
            $table->string('source_type', 40)->nullable();
            $table->unsignedBigInteger('source_id')->nullable();
            $table->string('source_reference', 80)->nullable();
            $table->string('cargo_description', 500)->nullable();
            $table->decimal('transport_charge', 18, 2)->default(0);
            $table->decimal('hire_cost', 18, 2)->default(0);
            // Fuel against the standard, worked out at completion and again at close.
            $table->decimal('standard_litres', 18, 3)->nullable();
            $table->decimal('actual_litres', 18, 3)->nullable();
            $table->decimal('fuel_variance_percent', 8, 2)->nullable();
            $table->decimal('fuel_tolerance_percent', 5, 2)->nullable();
            $table->boolean('fuel_over_standard')->default(false);
            $table->foreignId('variance_approved_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('variance_approved_at')->nullable();
            $table->string('variance_note', 255)->nullable();
            $table->string('status', 20)->default('planned');
            $table->string('notes', 1000)->nullable();
            $table->string('cancel_reason', 255)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('dispatched_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('dispatched_at')->nullable();
            $table->foreignId('completed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('completed_at')->nullable();
            $table->foreignId('closed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('closed_at')->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
            $table->index(['company_id', 'vehicle_id', 'planned_start']);
            $table->index(['company_id', 'source_type', 'source_id']);
        });

        Schema::create('fleet_fuel_issues', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('trip_id')->constrained('fleet_trips')->cascadeOnDelete();
            $table->foreignId('vehicle_id')->nullable()->constrained('fleet_vehicles')->nullOnDelete();
            $table->date('issue_date');
            $table->decimal('litres', 18, 3);
            $table->decimal('price_per_litre', 18, 2);
            $table->decimal('amount', 18, 2);
            $table->string('station', 120)->nullable();
            $table->string('receipt_number', 60)->nullable();
            $table->decimal('odometer', 18, 1)->nullable();
            // Paid from a cash or bank account, or on credit from a supplier.
            $table->foreignId('account_id')->nullable()->constrained('accounts')->nullOnDelete();
            $table->foreignId('supplier_id')->nullable()->constrained('suppliers')->nullOnDelete();
            $table->string('status', 12)->default('pending');
            $table->foreignId('recorded_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('approved_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('approved_at')->nullable();
            $table->string('rejection_reason', 255)->nullable();
            $table->timestamps();

            $table->index(['company_id', 'issue_date']);
        });

        Schema::create('fleet_trip_expenses', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('trip_id')->constrained('fleet_trips')->cascadeOnDelete();
            // allowance | toll | parking | loading | other
            $table->string('type', 20);
            $table->string('description', 255)->nullable();
            $table->date('expense_date');
            $table->decimal('quantity', 18, 3)->default(1);
            $table->decimal('rate', 18, 2);
            $table->decimal('amount', 18, 2);
            $table->string('receipt_number', 60)->nullable();
            $table->foreignId('account_id')->nullable()->constrained('accounts')->nullOnDelete();
            $table->foreignId('supplier_id')->nullable()->constrained('suppliers')->nullOnDelete();
            $table->string('status', 12)->default('pending');
            $table->foreignId('recorded_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('approved_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('approved_at')->nullable();
            $table->string('rejection_reason', 255)->nullable();
            $table->timestamps();

            $table->index(['company_id', 'trip_id']);
        });

        Schema::create('fleet_cost_allocations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('vehicle_id')->constrained('fleet_vehicles')->cascadeOnDelete();
            $table->foreignId('trip_id')->constrained('fleet_trips')->cascadeOnDelete();
            $table->string('period', 7);
            $table->string('basis', 10);
            // Days or km the trip used in the period, and what the period costs.
            $table->decimal('share', 18, 3);
            $table->decimal('period_units', 18, 3);
            $table->decimal('monthly_fixed_cost', 18, 2);
            $table->decimal('amount', 18, 2);
            $table->timestamps();

            $table->unique(['trip_id', 'period']);
            $table->index(['company_id', 'vehicle_id', 'period']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fleet_cost_allocations');
        Schema::dropIfExists('fleet_trip_expenses');
        Schema::dropIfExists('fleet_fuel_issues');
        Schema::dropIfExists('fleet_trips');
    }
};
