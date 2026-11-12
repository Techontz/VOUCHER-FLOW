<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/*
 * HR people: the employee profile that extends a user, the contracts that
 * carry pay, and the history of transfers and promotions. Plus the per-company
 * HR settings and the statutory rates payroll reads, which are data with
 * effective dates, never code.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('hr_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('country', 2)->default('TZ');
            $table->boolean('sdl_exempt')->default(false);
            $table->boolean('deduct_absence')->default(true);
            $table->decimal('working_days_per_month', 5, 2)->default(26);
            $table->decimal('hours_per_day', 4, 2)->default(8);
            $table->decimal('overtime_multiplier', 4, 2)->default(1.5);
            $table->timestamps();
        });

        Schema::create('hr_statutory_rates', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('country', 2);
            $table->string('code', 30);
            $table->string('name');
            $table->string('kind', 10);
            $table->string('base', 10);
            $table->string('party', 10);
            $table->decimal('rate', 8, 4)->nullable();
            $table->json('bands')->nullable();
            $table->date('effective_from');
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'country', 'code', 'effective_from'], 'hr_rates_unique');
        });

        Schema::create('hr_shifts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->time('start_time');
            $table->time('end_time');
            $table->unsignedSmallInteger('grace_minutes')->default(10);
            $table->boolean('is_default')->default(false);
            $table->timestamps();

            $table->unique(['company_id', 'name']);
        });

        Schema::create('hr_employees', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('employee_number', 40);
            $table->string('full_name');
            $table->string('email')->nullable();
            $table->string('phone', 40)->nullable();
            $table->string('national_id', 40)->nullable();
            $table->string('tin', 40)->nullable();
            $table->string('nssf_number', 40)->nullable();
            $table->date('date_of_birth')->nullable();
            $table->string('gender', 10)->nullable();
            $table->string('address')->nullable();
            $table->string('next_of_kin_name')->nullable();
            $table->string('next_of_kin_phone', 40)->nullable();
            $table->string('next_of_kin_relation', 60)->nullable();
            $table->string('bank_name')->nullable();
            $table->string('bank_account_number', 60)->nullable();
            $table->string('employment_type', 20)->default('permanent');
            $table->string('job_title')->nullable();
            $table->string('grade', 20)->nullable();
            $table->foreignId('department_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('manager_id')->nullable()->constrained('hr_employees')->nullOnDelete();
            $table->foreignId('shift_id')->nullable()->constrained('hr_shifts')->nullOnDelete();
            $table->date('hire_date');
            $table->date('probation_end')->nullable();
            $table->boolean('heslb_beneficiary')->default(false);
            $table->string('status', 12)->default('active');
            $table->date('exit_date')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'employee_number']);
            $table->unique(['company_id', 'user_id']);
            $table->index(['company_id', 'status']);
            $table->index(['company_id', 'department_id']);
        });

        Schema::create('hr_contracts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('employee_id')->constrained('hr_employees')->cascadeOnDelete();
            $table->string('type', 20);
            $table->date('start_date');
            $table->date('end_date')->nullable();
            $table->decimal('basic_salary', 18, 2);
            $table->decimal('housing_allowance', 18, 2)->default(0);
            $table->decimal('transport_allowance', 18, 2)->default(0);
            $table->decimal('other_allowance', 18, 2)->default(0);
            $table->string('status', 12)->default('active');
            $table->string('notes', 500)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['company_id', 'employee_id', 'status']);
            $table->index(['company_id', 'end_date']);
        });

        Schema::create('hr_movements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('employee_id')->constrained('hr_employees')->cascadeOnDelete();
            $table->string('type', 20);
            $table->date('effective_date');
            $table->foreignId('from_department_id')->nullable()->constrained('departments')->nullOnDelete();
            $table->foreignId('to_department_id')->nullable()->constrained('departments')->nullOnDelete();
            $table->string('from_job_title')->nullable();
            $table->string('to_job_title')->nullable();
            $table->string('from_grade', 20)->nullable();
            $table->string('to_grade', 20)->nullable();
            $table->string('reason', 500)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['company_id', 'employee_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('hr_movements');
        Schema::dropIfExists('hr_contracts');
        Schema::dropIfExists('hr_employees');
        Schema::dropIfExists('hr_shifts');
        Schema::dropIfExists('hr_statutory_rates');
        Schema::dropIfExists('hr_settings');
    }
};
