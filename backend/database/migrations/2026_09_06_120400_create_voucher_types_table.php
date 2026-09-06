<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('voucher_types', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('name_sw')->nullable();
            $table->string('code', 20);

            // Numbering: {prefix}-{year}-{seq}, e.g. PV-2026-001246
            $table->string('prefix', 10);
            $table->string('number_format')->default('{prefix}-{year}-{seq}');
            $table->unsignedTinyInteger('seq_padding')->default(6);
            $table->unsignedInteger('next_number')->default(1);
            $table->boolean('reset_yearly')->default(true);
            $table->unsignedSmallInteger('current_year')->nullable();

            $table->boolean('is_active')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();

            $table->unique(['company_id', 'code']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('voucher_types');
    }
};
