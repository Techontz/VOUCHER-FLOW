<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Licensing apps separately from switching them on.
 *
 * A company's subscription decides which apps it may use (licensed_modules,
 * NULL meaning every app, which is what existing companies keep); its
 * administrator then switches on any of those in Business setup (modules).
 * A plan either bundles a fixed set of apps or lets the customer pick from
 * its apps, priced at a base plus a price per app. Additive only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            $table->boolean('allows_module_choice')->default(false)->after('modules');
            $table->decimal('price_per_module', 14, 2)->default(0)->after('allows_module_choice');
        });

        Schema::table('companies', function (Blueprint $table) {
            $table->json('licensed_modules')->nullable()->after('modules');
        });
    }

    public function down(): void
    {
        Schema::table('companies', function (Blueprint $table) {
            $table->dropColumn('licensed_modules');
        });

        Schema::table('plans', function (Blueprint $table) {
            $table->dropColumn(['allows_module_choice', 'price_per_module']);
        });
    }
};
