<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The interface colour a company works in.
 *
 * Separate from primary_color, which is the brand colour printed on the
 * voucher: a document can carry any hex a brand guideline asks for, but the
 * interface only offers palettes that were tuned for contrast in both light
 * and dark mode. Every existing company starts on blue, which is what they
 * see today.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('companies', function (Blueprint $table) {
            $table->string('color_theme', 20)->default('blue')->after('theme');
        });
    }

    public function down(): void
    {
        Schema::table('companies', function (Blueprint $table) {
            $table->dropColumn('color_theme');
        });
    }
};
