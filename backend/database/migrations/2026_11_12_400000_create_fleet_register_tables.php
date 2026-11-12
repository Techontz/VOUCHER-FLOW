<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The fleet register: vehicles (owned or hired), the drivers who drive them
 * and the fuel each is expected to burn.
 *
 * A vehicle carries its own monthly fixed costs (insurance, licence,
 * depreciation) as configured figures; trips absorb them through
 * fleet_cost_allocations, never through the vehicle row itself.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fleet_vehicles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('registration_number', 30);
            $table->string('make', 60)->nullable();
            $table->string('model', 60)->nullable();
            $table->string('type', 30)->default('truck');
            $table->unsignedSmallInteger('year')->nullable();
            $table->decimal('capacity', 18, 3)->nullable();
            $table->string('capacity_unit', 20)->default('tonnes');
            $table->string('ownership', 10)->default('owned');
            // Hired vehicles: who owns it, and how the hire is charged.
            $table->foreignId('supplier_id')->nullable()->constrained('suppliers')->nullOnDelete();
            $table->string('hire_rate_basis', 10)->nullable();
            $table->decimal('hire_rate', 18, 2)->nullable();
            // A wet hire: the owner pays the fuel, so the company never expenses it.
            $table->boolean('hire_includes_fuel')->default(false);
            $table->decimal('odometer', 18, 1)->default(0);
            $table->string('status', 20)->default('available');
            $table->string('insurance_policy_number', 60)->nullable();
            $table->string('insurer', 120)->nullable();
            $table->date('insurance_expiry')->nullable();
            $table->string('road_licence_number', 60)->nullable();
            $table->date('road_licence_expiry')->nullable();
            // Monthly fixed costs, allocated to trips by days or km.
            $table->decimal('monthly_insurance', 18, 2)->default(0);
            $table->decimal('monthly_licence', 18, 2)->default(0);
            $table->decimal('monthly_depreciation', 18, 2)->default(0);
            $table->decimal('monthly_other_fixed', 18, 2)->default(0);
            $table->string('allocation_basis', 10)->default('days');
            $table->decimal('expected_monthly_km', 18, 1)->nullable();
            $table->string('notes', 1000)->nullable();
            $table->boolean('is_active')->default(true);
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'registration_number']);
            $table->index(['company_id', 'status']);
        });

        Schema::create('fleet_drivers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('licence_number', 40);
            $table->string('licence_class', 20)->nullable();
            $table->date('licence_expiry')->nullable();
            $table->string('phone', 40)->nullable();
            $table->foreignId('vehicle_id')->nullable()->constrained('fleet_vehicles')->nullOnDelete();
            $table->decimal('daily_allowance', 18, 2)->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['company_id', 'user_id']);
            $table->unique(['company_id', 'licence_number']);
        });

        Schema::create('fleet_fuel_standards', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            // Either or both: a vehicle, a route. The most specific match wins.
            $table->foreignId('vehicle_id')->nullable()->constrained('fleet_vehicles')->cascadeOnDelete();
            $table->string('origin', 80)->nullable();
            $table->string('destination', 80)->nullable();
            $table->string('basis', 12)->default('per_100km');
            $table->decimal('litres', 18, 3);
            $table->decimal('tolerance_percent', 5, 2)->default(10);
            $table->string('notes', 255)->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['company_id', 'vehicle_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fleet_fuel_standards');
        Schema::dropIfExists('fleet_drivers');
        Schema::dropIfExists('fleet_vehicles');
    }
};
