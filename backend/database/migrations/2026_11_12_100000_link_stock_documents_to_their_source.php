<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A stock document raised by another module (a loading order, a production
 * order, a purchase order) records that source, and may name the account its
 * posting charges instead of the type's default: cost of goods sold for a
 * sale, work in progress for production.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('stock_documents', function (Blueprint $table) {
            $table->string('source_type', 60)->nullable()->after('reason');
            $table->unsignedBigInteger('source_id')->nullable()->after('source_type');
            $table->string('contra_account', 40)->nullable()->after('source_id');
            $table->index(['company_id', 'source_type', 'source_id']);
        });
    }

    public function down(): void
    {
        Schema::table('stock_documents', function (Blueprint $table) {
            $table->dropIndex(['company_id', 'source_type', 'source_id']);
            $table->dropColumn(['source_type', 'source_id', 'contra_account']);
        });
    }
};
