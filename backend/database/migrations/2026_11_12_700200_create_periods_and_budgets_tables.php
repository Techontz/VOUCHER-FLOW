<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Period closing and budgets.
 *
 * A closed period is a month nothing may be posted into. Reopening keeps the
 * row (status open) so the history of who closed and reopened it stays.
 * A year-end closing is the one entry that moves a year's profit into
 * retained earnings; the unique year holds it to once.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('closed_periods', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            // YYYY-MM
            $table->string('period', 7);
            $table->date('starts_on');
            $table->date('ends_on');
            // closed · open (reopened)
            $table->string('status', 20)->default('closed');
            $table->foreignId('closed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('closed_at')->nullable();
            $table->foreignId('reopened_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reopened_at')->nullable();
            $table->string('reopen_reason', 255)->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'period']);
            $table->index(['company_id', 'status', 'starts_on', 'ends_on']);
        });

        Schema::create('year_end_closings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->unsignedSmallInteger('fiscal_year');
            $table->date('starts_on');
            $table->date('ends_on');
            $table->decimal('net_profit', 18, 2);
            $table->foreignId('journal_entry_id')->nullable()->constrained('journal_entries')->nullOnDelete();
            $table->foreignId('closed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'fiscal_year']);
        });

        Schema::create('budgets', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->unsignedSmallInteger('fiscal_year');
            $table->string('name', 120);
            $table->string('notes', 500)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'fiscal_year']);
        });

        Schema::create('budget_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('budget_id')->constrained()->cascadeOnDelete();
            $table->foreignId('account_id')->constrained('accounts')->restrictOnDelete();
            // 1-12, the month of the fiscal year.
            $table->unsignedTinyInteger('month');
            $table->decimal('amount', 18, 2)->default(0);
            $table->timestamps();

            $table->unique(['budget_id', 'account_id', 'month']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('budget_lines');
        Schema::dropIfExists('budgets');
        Schema::dropIfExists('year_end_closings');
        Schema::dropIfExists('closed_periods');
    }
};
