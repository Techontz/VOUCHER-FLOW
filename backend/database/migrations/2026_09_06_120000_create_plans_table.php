<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('plans', function (Blueprint $table) {
            $table->id();
            $table->string('code')->unique();
            $table->string('name');
            $table->string('name_sw')->nullable();
            $table->string('blurb')->nullable();
            $table->string('blurb_sw')->nullable();
            $table->decimal('price', 12, 2)->default(0);
            $table->char('currency', 3)->default('TZS');
            $table->enum('billing_cycle', ['monthly', 'annual'])->default('monthly');

            // NULL on any limit means "unlimited".
            $table->unsignedInteger('max_users')->nullable();
            $table->unsignedInteger('max_vouchers_per_month')->nullable();
            $table->unsignedInteger('max_departments')->nullable();
            $table->unsignedInteger('max_approval_levels')->nullable();
            $table->unsignedInteger('storage_mb')->nullable();

            $table->unsignedSmallInteger('trial_days')->default(14);
            $table->json('features')->nullable();
            $table->boolean('is_active')->default(true);
            $table->boolean('is_public')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('plans');
    }
};
