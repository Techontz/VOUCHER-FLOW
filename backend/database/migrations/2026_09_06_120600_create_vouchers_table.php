<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('vouchers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);

            $table->foreignId('voucher_type_id')->constrained()->restrictOnDelete();
            $table->foreignId('workflow_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('department_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('requester_id')->constrained('users')->restrictOnDelete();

            $table->string('payee');
            $table->string('purpose');
            $table->text('description')->nullable();
            $table->decimal('amount', 18, 2)->default(0);
            $table->char('currency', 3)->default('TZS');
            $table->string('amount_in_words')->nullable();

            $table->string('payment_method')->nullable();
            $table->string('account_ref')->nullable();
            $table->string('category')->nullable();
            $table->string('cost_centre')->nullable();
            $table->date('voucher_date');

            $table->enum('status', [
                'draft', 'in_review', 'changes_requested', 'approved', 'rejected', 'cancelled',
            ])->default('draft');

            // Position within the voucher's own workflow. Combined with step_signed_at
            // this expresses "signed at this step but not yet submitted onward".
            $table->unsignedSmallInteger('current_step_position')->nullable();
            $table->timestamp('step_signed_at')->nullable();

            $table->string('verification_code', 20)->nullable()->unique();
            $table->text('notes_to_approver')->nullable();

            $table->timestamp('submitted_at')->nullable();
            $table->timestamp('approved_at')->nullable();
            $table->timestamp('rejected_at')->nullable();

            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();

            $table->timestamps();
            $table->softDeletes();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
            $table->index(['company_id', 'requester_id']);
            $table->index(['company_id', 'department_id']);
            $table->index(['company_id', 'voucher_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('vouchers');
    }
};
