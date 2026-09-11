<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The workflow used to end at "approved", which left the cashier with nothing to
 * record against. A voucher is not finished when someone agrees to pay it; it is
 * finished when the money has actually moved, and the document has to be able to
 * say who moved it, when, and against what reference.
 *
 * The same migration splits bank from cash. They are different instruments: one
 * settles into an account and is reconciled against a statement, the other comes
 * out of a float and is acknowledged by a signature on the day. Carrying both in
 * one undifferentiated set of columns meant the form had to ask a cash claimant
 * for a branch name.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('vouchers', function (Blueprint $table) {
            $table->string('kind', 8)->default('bank')->after('voucher_type_id');

            // Who released the money, and the tenant's own reference for it.
            $table->timestamp('paid_at')->nullable()->after('rejected_at');
            $table->unsignedBigInteger('paid_by_id')->nullable()->after('paid_at');
            $table->string('payment_reference')->nullable()->after('paid_by_id');
            $table->date('payment_date')->nullable()->after('payment_reference');

            // Bank particulars — the payee's account, not the company's.
            $table->string('payee_bank')->nullable()->after('account_ref');
            $table->string('payee_account_name')->nullable()->after('payee_bank');
            $table->string('payee_account_number', 64)->nullable()->after('payee_account_name');
            $table->string('payee_bank_branch')->nullable()->after('payee_account_number');
            $table->string('cheque_number', 64)->nullable()->after('payee_bank_branch');

            // Cash particulars — which float it came out of, and who took it.
            $table->string('cash_float')->nullable()->after('cheque_number');
            $table->string('received_by')->nullable()->after('cash_float');

            $table->foreign('paid_by_id')->references('id')->on('users')->nullOnDelete();

            // The cashier's queue is "approved, unpaid, this company".
            $table->index(['company_id', 'status', 'kind'], 'vouchers_company_status_kind_index');
        });

        DB::statement("
            ALTER TABLE vouchers MODIFY status
            ENUM('draft','in_review','changes_requested','approved','rejected','cancelled','paid')
            NOT NULL DEFAULT 'draft'
        ");
    }

    public function down(): void
    {
        DB::statement("UPDATE vouchers SET status = 'approved' WHERE status = 'paid'");
        DB::statement("
            ALTER TABLE vouchers MODIFY status
            ENUM('draft','in_review','changes_requested','approved','rejected','cancelled')
            NOT NULL DEFAULT 'draft'
        ");

        Schema::table('vouchers', function (Blueprint $table) {
            $table->dropForeign(['paid_by_id']);
            $table->dropIndex('vouchers_company_status_kind_index');
            $table->dropColumn([
                'kind', 'paid_at', 'paid_by_id', 'payment_reference', 'payment_date',
                'payee_bank', 'payee_account_name', 'payee_account_number',
                'payee_bank_branch', 'cheque_number', 'cash_float', 'received_by',
            ]);
        });
    }
};
