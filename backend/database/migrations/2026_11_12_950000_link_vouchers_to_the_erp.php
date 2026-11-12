<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * VouchFlow and the books, joined.
 *
 * A voucher may be raised from an ERP document (a supplier invoice today)
 * and carries a reference back to it; or it may name the account its payment
 * charges. Each payment released on such a voucher records what it posted:
 * the supplier payment that cleared the invoice, or the journal entry.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('vouchers', function (Blueprint $table) {
            $table->string('source_type', 60)->nullable()->after('notes_to_approver');
            $table->unsignedBigInteger('source_id')->nullable()->after('source_type');
            $table->string('source_label', 160)->nullable()->after('source_id');
            $table->foreignId('ledger_account_id')->nullable()->after('source_label')->constrained('accounts')->nullOnDelete();
            $table->index(['company_id', 'source_type', 'source_id']);
        });

        Schema::table('voucher_payments', function (Blueprint $table) {
            $table->unsignedBigInteger('supplier_payment_id')->nullable()->after('note');
            $table->unsignedBigInteger('journal_entry_id')->nullable()->after('supplier_payment_id');
        });
    }

    public function down(): void
    {
        Schema::table('voucher_payments', function (Blueprint $table) {
            $table->dropColumn(['supplier_payment_id', 'journal_entry_id']);
        });

        Schema::table('vouchers', function (Blueprint $table) {
            $table->dropIndex(['company_id', 'source_type', 'source_id']);
            $table->dropConstrainedForeignId('ledger_account_id');
            $table->dropColumn(['source_type', 'source_id', 'source_label']);
        });
    }
};
