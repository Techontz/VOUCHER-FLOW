<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/*
 * Payroll: monthly runs and their payslips, loans and advances with their
 * repayments, and the one-off or recurring earnings and deductions a run
 * picks up. A payslip stores every figure it was paid on, so a later change
 * to a contract or a rate never rewrites history.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('hr_payroll_runs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->string('period', 7);
            $table->date('period_start');
            $table->date('period_end');
            $table->string('status', 12)->default('draft');
            $table->unsignedInteger('employees_count')->default(0);
            foreach (['basic', 'allowances', 'overtime', 'other_earnings', 'absence_deduction', 'gross', 'nssf_employee', 'paye', 'heslb', 'loans', 'other_deductions', 'total_deductions', 'net', 'nssf_employer', 'wcf', 'sdl'] as $column) {
                $table->decimal($column, 18, 2)->default(0);
            }
            $table->json('rates')->nullable();
            $table->string('notes', 500)->nullable();
            $table->foreignId('prepared_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('prepared_at')->nullable();
            $table->foreignId('authorised_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('authorised_at')->nullable();
            $table->foreignId('locked_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('locked_at')->nullable();
            $table->foreignId('posted_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('posted_at')->nullable();
            $table->foreignId('journal_entry_id')->nullable()->constrained('journal_entries')->nullOnDelete();
            $table->foreignId('paid_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('paid_at')->nullable();
            $table->date('payment_date')->nullable();
            $table->foreignId('payment_account_id')->nullable()->constrained('accounts')->nullOnDelete();
            $table->foreignId('payment_journal_id')->nullable()->constrained('journal_entries')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'period']);
            $table->unique(['company_id', 'number']);
        });

        Schema::create('hr_payslips', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('payroll_run_id')->constrained('hr_payroll_runs')->cascadeOnDelete();
            $table->foreignId('employee_id')->constrained('hr_employees');
            $table->string('employee_number', 40);
            $table->string('employee_name');
            $table->string('department')->nullable();
            $table->string('job_title')->nullable();
            $table->string('bank_name')->nullable();
            $table->string('bank_account_number', 60)->nullable();
            $table->decimal('days_paid', 5, 2)->default(0);
            $table->decimal('unpaid_days', 5, 2)->default(0);
            $table->decimal('overtime_hours', 6, 2)->default(0);
            foreach (['basic', 'housing_allowance', 'transport_allowance', 'other_allowance', 'overtime', 'other_earnings', 'absence_deduction', 'gross', 'nssf_employee', 'taxable', 'paye', 'heslb', 'loans', 'other_deductions', 'total_deductions', 'net', 'nssf_employer', 'wcf', 'sdl'] as $column) {
                $table->decimal($column, 18, 2)->default(0);
            }
            $table->json('lines')->nullable();
            $table->timestamps();

            $table->unique(['payroll_run_id', 'employee_id']);
            $table->index(['company_id', 'employee_id']);
        });

        Schema::create('hr_loans', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('employee_id')->constrained('hr_employees')->cascadeOnDelete();
            $table->string('number', 40);
            $table->string('type', 10);
            $table->decimal('principal', 18, 2);
            $table->decimal('installment', 18, 2);
            $table->decimal('balance', 18, 2);
            $table->string('start_period', 7);
            $table->date('issued_on');
            $table->string('reason', 500)->nullable();
            $table->string('status', 12)->default('active');
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
        });

        Schema::create('hr_loan_repayments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('loan_id')->constrained('hr_loans')->cascadeOnDelete();
            $table->foreignId('payroll_run_id')->nullable()->constrained('hr_payroll_runs')->nullOnDelete();
            $table->string('period', 7);
            $table->decimal('amount', 18, 2);
            $table->decimal('balance_after', 18, 2);
            $table->timestamps();

            $table->unique(['loan_id', 'payroll_run_id']);
        });

        Schema::create('hr_pay_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('employee_id')->constrained('hr_employees')->cascadeOnDelete();
            $table->string('kind', 10);
            $table->string('category', 20);
            $table->string('description');
            $table->decimal('amount', 18, 2);
            $table->string('start_period', 7);
            $table->string('end_period', 7)->nullable();
            $table->boolean('is_active')->default(true);
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['company_id', 'employee_id', 'is_active']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('hr_pay_items');
        Schema::dropIfExists('hr_loan_repayments');
        Schema::dropIfExists('hr_loans');
        Schema::dropIfExists('hr_payslips');
        Schema::dropIfExists('hr_payroll_runs');
    }
};
