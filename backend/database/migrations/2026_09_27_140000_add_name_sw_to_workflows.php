<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A workflow's name is shown to Swahili-speaking staff too — on the voucher
 * timeline and in the builder — so it carries a Swahili name like its steps do.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('workflows', function (Blueprint $table) {
            $table->string('name_sw')->nullable()->after('name');
        });
    }

    public function down(): void
    {
        Schema::table('workflows', function (Blueprint $table) {
            $table->dropColumn('name_sw');
        });
    }
};
