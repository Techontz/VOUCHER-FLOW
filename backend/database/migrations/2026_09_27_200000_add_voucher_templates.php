<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Voucher templates: how a company's vouchers look, never how they work.
 *
 * - companies.voucher_template is the design new documents render in, and
 *   voucher_template_changes_used counts the self-service changes the company
 *   has spent (the allowance itself lives in config, so it can be raised
 *   without a migration).
 * - vouchers.voucher_template is a snapshot. It stays null while a voucher is
 *   still moving, so it follows the company's current design; once a voucher
 *   is finalised and the company later changes design, the old design is
 *   written here so the issued document never changes under anybody.
 * - voucher_template_changes is the history the platform reads back.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('companies', function (Blueprint $table) {
            $table->string('voucher_template', 40)->default('classic')->after('voucher_footer_text');
            $table->unsignedTinyInteger('voucher_template_changes_used')->default(0)->after('voucher_template');
        });

        Schema::table('vouchers', function (Blueprint $table) {
            $table->string('voucher_template', 40)->nullable();
        });

        Schema::create('voucher_template_changes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('previous_template', 40)->nullable();
            $table->string('new_template', 40);
            $table->foreignId('changed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('changed_by_name')->nullable();
            $table->string('changed_by_role', 40)->nullable();
            // registration | company_admin | super_admin | platform_create
            $table->string('source', 30);
            $table->string('reason', 500)->nullable();
            // Whether this change spent one of the company's own changes.
            $table->boolean('counted')->default(false);
            $table->timestamp('created_at')->nullable();

            $table->index(['company_id', 'id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('voucher_template_changes');

        Schema::table('vouchers', function (Blueprint $table) {
            $table->dropColumn('voucher_template');
        });

        Schema::table('companies', function (Blueprint $table) {
            $table->dropColumn(['voucher_template', 'voucher_template_changes_used']);
        });
    }
};
