<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Keeping vehicles on the road: service schedules by km or by date, the
 * service records that satisfy them, tyres by position and the time a
 * vehicle spends off the road.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fleet_maintenance_schedules', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('vehicle_id')->constrained('fleet_vehicles')->cascadeOnDelete();
            $table->string('title', 120);
            $table->unsignedInteger('interval_km')->nullable();
            $table->unsignedInteger('interval_days')->nullable();
            $table->decimal('last_done_odometer', 18, 1)->nullable();
            $table->date('last_done_date')->nullable();
            $table->decimal('next_due_odometer', 18, 1)->nullable();
            $table->date('next_due_date')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['company_id', 'vehicle_id']);
        });

        Schema::create('fleet_service_records', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 30);
            $table->foreignId('vehicle_id')->constrained('fleet_vehicles')->restrictOnDelete();
            $table->foreignId('schedule_id')->nullable()->constrained('fleet_maintenance_schedules')->nullOnDelete();
            $table->date('service_date');
            $table->decimal('odometer', 18, 1)->nullable();
            $table->string('work_done', 1000);
            $table->decimal('cost', 18, 2)->default(0);
            // The garage, on credit; or paid from a cash or bank account.
            $table->foreignId('supplier_id')->nullable()->constrained('suppliers')->nullOnDelete();
            $table->foreignId('account_id')->nullable()->constrained('accounts')->nullOnDelete();
            $table->string('invoice_number', 60)->nullable();
            $table->string('status', 12)->default('draft');
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('posted_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('posted_at')->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'vehicle_id', 'service_date']);
        });

        Schema::create('fleet_tyres', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('vehicle_id')->constrained('fleet_vehicles')->cascadeOnDelete();
            $table->string('position', 30);
            $table->string('serial_number', 60);
            $table->string('brand', 60)->nullable();
            $table->string('size', 30)->nullable();
            $table->decimal('cost', 18, 2)->default(0);
            $table->date('fitted_date');
            $table->decimal('fitted_odometer', 18, 1);
            $table->date('removed_date')->nullable();
            $table->decimal('removed_odometer', 18, 1)->nullable();
            $table->string('removal_reason', 255)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'serial_number']);
            $table->index(['company_id', 'vehicle_id']);
        });

        Schema::create('fleet_downtimes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('vehicle_id')->constrained('fleet_vehicles')->cascadeOnDelete();
            $table->foreignId('service_record_id')->nullable()->constrained('fleet_service_records')->nullOnDelete();
            // maintenance | breakdown | accident | other
            $table->string('reason', 20);
            $table->string('description', 255)->nullable();
            $table->dateTime('started_at');
            $table->dateTime('ended_at')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['company_id', 'vehicle_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fleet_downtimes');
        Schema::dropIfExists('fleet_tyres');
        Schema::dropIfExists('fleet_service_records');
        Schema::dropIfExists('fleet_maintenance_schedules');
    }
};
