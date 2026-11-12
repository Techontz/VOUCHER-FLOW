<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/*
 * The rest of the employee life cycle: recruitment and onboarding,
 * appraisals and training, discipline, and exit with clearance.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('hr_vacancies', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('title');
            $table->foreignId('department_id')->nullable()->constrained()->nullOnDelete();
            $table->unsignedSmallInteger('positions')->default(1);
            $table->string('employment_type', 20)->default('permanent');
            $table->string('location')->nullable();
            $table->text('description')->nullable();
            $table->date('closing_date')->nullable();
            $table->string('status', 10)->default('open');
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['company_id', 'status']);
        });

        Schema::create('hr_applicants', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('vacancy_id')->constrained('hr_vacancies')->cascadeOnDelete();
            $table->string('name');
            $table->string('email')->nullable();
            $table->string('phone', 40)->nullable();
            $table->string('stage', 12)->default('applied');
            $table->string('notes', 1000)->nullable();
            $table->foreignId('employee_id')->nullable()->constrained('hr_employees')->nullOnDelete();
            $table->timestamps();

            $table->index(['company_id', 'stage']);
        });

        Schema::create('hr_onboarding_tasks', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('employee_id')->constrained('hr_employees')->cascadeOnDelete();
            $table->string('title');
            $table->unsignedSmallInteger('sort')->default(0);
            $table->timestamp('done_at')->nullable();
            $table->foreignId('done_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });

        Schema::create('hr_appraisal_periods', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->date('start_date');
            $table->date('end_date');
            $table->string('status', 10)->default('open');
            $table->timestamps();
        });

        Schema::create('hr_appraisals', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('period_id')->constrained('hr_appraisal_periods')->cascadeOnDelete();
            $table->foreignId('employee_id')->constrained('hr_employees')->cascadeOnDelete();
            $table->foreignId('reviewer_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('status', 12)->default('draft');
            $table->decimal('overall_rating', 4, 2)->nullable();
            $table->text('employee_comments')->nullable();
            $table->text('reviewer_comments')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamps();

            $table->unique(['period_id', 'employee_id']);
        });

        Schema::create('hr_appraisal_objectives', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('appraisal_id')->constrained('hr_appraisals')->cascadeOnDelete();
            $table->string('title');
            $table->string('target')->nullable();
            $table->unsignedTinyInteger('weight')->default(1);
            $table->unsignedTinyInteger('rating')->nullable();
            $table->string('comment', 500)->nullable();
            $table->timestamps();
        });

        Schema::create('hr_trainings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('employee_id')->constrained('hr_employees')->cascadeOnDelete();
            $table->string('title');
            $table->string('provider')->nullable();
            $table->date('start_date');
            $table->date('end_date')->nullable();
            $table->decimal('cost', 18, 2)->default(0);
            $table->string('status', 12)->default('planned');
            $table->string('notes', 500)->nullable();
            $table->timestamps();
        });

        Schema::create('hr_discipline_cases', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('employee_id')->constrained('hr_employees')->cascadeOnDelete();
            $table->string('number', 40);
            $table->string('category', 30);
            $table->date('incident_date');
            $table->text('description');
            $table->string('action', 20)->nullable();
            $table->string('status', 10)->default('open');
            $table->text('outcome')->nullable();
            $table->foreignId('opened_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('closed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('closed_at')->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
        });

        Schema::create('hr_separations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('employee_id')->constrained('hr_employees')->cascadeOnDelete();
            $table->string('type', 20);
            $table->date('notice_date');
            $table->date('last_working_day');
            $table->string('reason', 1000)->nullable();
            $table->string('status', 12)->default('in_progress');
            $table->decimal('leave_days_payable', 6, 2)->default(0);
            $table->decimal('leave_pay', 18, 2)->default(0);
            $table->decimal('other_dues', 18, 2)->default(0);
            $table->decimal('outstanding_loans', 18, 2)->default(0);
            $table->decimal('final_dues', 18, 2)->default(0);
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('completed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('completed_at')->nullable();
            $table->timestamps();
        });

        Schema::create('hr_clearance_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('separation_id')->constrained('hr_separations')->cascadeOnDelete();
            $table->foreignId('department_id')->nullable()->constrained()->nullOnDelete();
            $table->string('area', 40);
            $table->string('item');
            $table->foreignId('cleared_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('cleared_at')->nullable();
            $table->string('note')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('hr_clearance_items');
        Schema::dropIfExists('hr_separations');
        Schema::dropIfExists('hr_discipline_cases');
        Schema::dropIfExists('hr_trainings');
        Schema::dropIfExists('hr_appraisal_objectives');
        Schema::dropIfExists('hr_appraisals');
        Schema::dropIfExists('hr_appraisal_periods');
        Schema::dropIfExists('hr_onboarding_tasks');
        Schema::dropIfExists('hr_applicants');
        Schema::dropIfExists('hr_vacancies');
    }
};
