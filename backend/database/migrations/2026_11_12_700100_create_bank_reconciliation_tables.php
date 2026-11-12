<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Bank reconciliation: a statement (opening and closing balance at a date)
 * and its lines, each matched to at most one journal line on the bank's
 * ledger account. A journal line can be matched once, ever, which is what
 * makes an item "reconciled": the unique key holds it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('bank_reconciliations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('bank_account_id')->constrained('bank_accounts')->restrictOnDelete();
            $table->string('number', 40);
            $table->date('statement_date');
            $table->decimal('statement_opening_balance', 18, 2)->default(0);
            $table->decimal('statement_closing_balance', 18, 2);
            // open · completed
            $table->string('status', 20)->default('open');
            $table->string('notes', 500)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('completed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('completed_at')->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
        });

        Schema::create('bank_statement_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('bank_reconciliation_id')->constrained()->cascadeOnDelete();
            $table->date('line_date');
            $table->string('description', 255);
            $table->string('reference', 80)->nullable();
            // Signed: money into the account is positive, money out negative.
            $table->decimal('amount', 18, 2);
            $table->foreignId('journal_line_id')->nullable()->unique()->constrained('journal_lines')->restrictOnDelete();
            $table->foreignId('matched_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('matched_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('bank_statement_lines');
        Schema::dropIfExists('bank_reconciliations');
    }
};
