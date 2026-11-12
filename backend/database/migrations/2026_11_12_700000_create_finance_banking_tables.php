<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Banking: the register of bank, mobile money and cash accounts, transfers
 * between them and the general cashbook.
 *
 * A bank account is a label on a general ledger account (1201-1299); its
 * balance is never stored here, it is read from the journal. Transfers and
 * cashbook entries are documents: draft, then posted exactly once, then
 * reversed if wrong, never edited once posted.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('bank_accounts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('account_id')->constrained('accounts')->restrictOnDelete();
            $table->string('name', 120);
            // bank · mobile_money · cash
            $table->string('type', 20)->default('bank');
            $table->string('bank_name', 120)->nullable();
            $table->string('branch', 120)->nullable();
            $table->string('account_name', 160)->nullable();
            $table->string('account_number', 60)->nullable();
            $table->string('currency', 3)->default('TZS');
            $table->decimal('opening_balance', 18, 2)->default(0);
            $table->date('opening_date')->nullable();
            $table->foreignId('opening_entry_id')->nullable()->constrained('journal_entries')->nullOnDelete();
            $table->boolean('is_active')->default(true);
            $table->string('notes', 500)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'account_id']);
        });

        Schema::create('bank_transfers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            $table->date('transfer_date');
            $table->foreignId('from_bank_account_id')->constrained('bank_accounts')->restrictOnDelete();
            $table->foreignId('to_bank_account_id')->constrained('bank_accounts')->restrictOnDelete();
            $table->decimal('amount', 18, 2);
            // Charged by the bank on the sending account, posted with the transfer.
            $table->decimal('charges', 18, 2)->default(0);
            $table->string('reference', 80)->nullable();
            $table->string('memo', 255)->nullable();
            $table->string('status', 20)->default('draft');
            $table->foreignId('journal_entry_id')->nullable()->constrained('journal_entries')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('posted_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('posted_at')->nullable();
            $table->foreignId('reversed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reversed_at')->nullable();
            $table->string('reversal_reason', 255)->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
        });

        Schema::create('cashbook_entries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            // receipt (money in) · payment (money out)
            $table->string('type', 20);
            $table->date('entry_date');
            $table->foreignId('bank_account_id')->constrained('bank_accounts')->restrictOnDelete();
            // The other side of the entry: income, expense, equity, liability...
            $table->foreignId('account_id')->constrained('accounts')->restrictOnDelete();
            $table->decimal('amount', 18, 2);
            $table->string('counterparty', 160)->nullable();
            $table->string('reference', 80)->nullable();
            $table->string('description', 255);
            $table->string('status', 20)->default('draft');
            $table->foreignId('journal_entry_id')->nullable()->constrained('journal_entries')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('posted_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('posted_at')->nullable();
            $table->foreignId('reversed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reversed_at')->nullable();
            $table->string('reversal_reason', 255)->nullable();
            $table->timestamps();

            $table->unique(['company_id', 'number']);
            $table->index(['company_id', 'status']);
            $table->index(['company_id', 'entry_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cashbook_entries');
        Schema::dropIfExists('bank_transfers');
        Schema::dropIfExists('bank_accounts');
    }
};
