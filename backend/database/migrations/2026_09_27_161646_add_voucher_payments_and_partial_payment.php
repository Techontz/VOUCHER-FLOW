<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Payments as their own records, so money can be released in parts.
 *
 * A voucher approved for 10,000,000 may be paid 9,000,000 now and the balance
 * later; each release is one row with its own amount, receiver, reference and
 * signed acknowledgement. The voucher keeps a running total paid, stays
 * approved (awaiting payment) while a balance remains, and becomes paid once
 * nothing is outstanding. Vouchers paid before this change get one payment
 * row for their full amount, so every paid voucher has its history.
 */
return new class extends Migration
{
    private const ACTIONS_BEFORE = "'created','submitted','signed','approved','rejected','changes_requested','resubmitted','forwarded','cancelled','paid'";

    private const ACTIONS_AFTER = "'created','submitted','signed','approved','rejected','changes_requested','resubmitted','forwarded','cancelled','paid','part_paid','acknowledged'";

    public function up(): void
    {
        Schema::table('vouchers', function (Blueprint $table) {
            $table->decimal('amount_paid', 18, 2)->default(0)->after('amount');
        });

        Schema::create('voucher_payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('voucher_id')->constrained()->cascadeOnDelete();
            $table->unsignedSmallInteger('sequence');
            $table->decimal('amount', 18, 2);
            $table->decimal('balance_after', 18, 2)->default(0);
            $table->string('currency', 3)->default('TZS');
            $table->string('payment_method', 80)->nullable();
            $table->string('payment_reference', 120)->nullable();
            $table->string('cheque_number', 64)->nullable();
            $table->string('received_by', 120)->nullable();
            $table->string('receiver_id_number', 60)->nullable();
            $table->date('payment_date')->nullable();
            $table->text('note')->nullable();
            $table->foreignId('paid_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->dateTime('paid_at');
            $table->dateTime('acknowledged_at')->nullable();
            $table->timestamps();

            $table->unique(['voucher_id', 'sequence']);
            $table->index(['company_id', 'paid_at']);
        });

        Schema::table('voucher_attachments', function (Blueprint $table) {
            $table->foreignId('voucher_payment_id')->nullable()->after('voucher_id')->constrained()->nullOnDelete();
            $table->string('document_type', 40)->nullable()->after('mime_type');
        });

        DB::statement('ALTER TABLE voucher_approvals MODIFY action ENUM('.self::ACTIONS_AFTER.') NOT NULL');

        // Every voucher already paid in full gets its single payment on record.
        DB::table('vouchers')->where('status', 'paid')->orderBy('id')->chunkById(500, function ($vouchers) {
            foreach ($vouchers as $v) {
                $paidAt = $v->paid_at ?? $v->updated_at ?? now();

                DB::table('voucher_payments')->insert([
                    'company_id' => $v->company_id,
                    'voucher_id' => $v->id,
                    'sequence' => 1,
                    'amount' => $v->amount,
                    'balance_after' => 0,
                    'currency' => $v->currency ?? 'TZS',
                    'payment_method' => $v->payment_method,
                    'payment_reference' => $v->payment_reference,
                    'cheque_number' => $v->cheque_number,
                    'received_by' => $v->received_by,
                    'payment_date' => $v->payment_date,
                    'paid_by_id' => $v->paid_by_id,
                    'paid_at' => $paidAt,
                    'created_at' => $paidAt,
                    'updated_at' => $paidAt,
                ]);

                DB::table('vouchers')->where('id', $v->id)->update(['amount_paid' => $v->amount]);
            }
        });
    }

    public function down(): void
    {
        DB::statement("DELETE FROM voucher_approvals WHERE action IN ('part_paid','acknowledged')");
        DB::statement('ALTER TABLE voucher_approvals MODIFY action ENUM('.self::ACTIONS_BEFORE.') NOT NULL');

        Schema::table('voucher_attachments', function (Blueprint $table) {
            $table->dropConstrainedForeignId('voucher_payment_id');
            $table->dropColumn('document_type');
        });

        Schema::dropIfExists('voucher_payments');

        Schema::table('vouchers', function (Blueprint $table) {
            $table->dropColumn('amount_paid');
        });
    }
};
