<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What a tenant needs in order for the printed voucher to be *their* document.
 *
 * A voucher is a financial instrument: whoever receives it expects the issuer's
 * registration number on it, and whoever reconciles it expects to know which
 * account the money leaves. Both were missing, which meant every tenant's PDF
 * had to fall back to the same anonymous letterhead.
 *
 * The square mark is stored separately from the lockup on purpose — a wordmark
 * crushed into a 34px avatar is unreadable, which is why brands ship both.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('companies', function (Blueprint $table) {
            $table->string('tin', 40)->nullable()->after('website');
            $table->string('registration_number', 60)->nullable()->after('tin');
            $table->string('logo_mark_path')->nullable()->after('logo_path');

            // The account the company pays FROM, printed on a bank voucher as
            // "drawn on". Distinct from the payee's account on the voucher.
            $table->string('bank_name')->nullable()->after('voucher_footer_text');
            $table->string('bank_account_name')->nullable()->after('bank_name');
            $table->string('bank_account_number', 64)->nullable()->after('bank_account_name');
            $table->string('bank_branch')->nullable()->after('bank_account_number');

            $table->string('voucher_header_text')->nullable()->after('bank_branch');
        });
    }

    public function down(): void
    {
        Schema::table('companies', function (Blueprint $table) {
            $table->dropColumn([
                'tin', 'registration_number', 'logo_mark_path',
                'bank_name', 'bank_account_name', 'bank_account_number', 'bank_branch',
                'voucher_header_text',
            ]);
        });
    }
};
