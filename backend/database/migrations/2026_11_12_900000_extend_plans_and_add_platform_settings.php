<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What the platform operator needs to run pricing and the platform itself.
 *
 * Plans gain a yearly price of their own (NULL keeps the old rule: ten months
 * for a year), the ERP modules they include and a featured flag for the
 * pricing page. Platform-wide defaults live in a small key/value table so the
 * operator can change them without a deploy. Additive only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            $table->decimal('price_yearly', 12, 2)->nullable()->after('price');
            $table->json('modules')->nullable()->after('features');
            $table->boolean('is_featured')->default(false)->after('is_public');
        });

        Schema::create('platform_settings', function (Blueprint $table) {
            $table->id();
            $table->string('key', 80)->unique();
            $table->json('value')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('platform_settings');

        Schema::table('plans', function (Blueprint $table) {
            $table->dropColumn(['price_yearly', 'modules', 'is_featured']);
        });
    }
};
