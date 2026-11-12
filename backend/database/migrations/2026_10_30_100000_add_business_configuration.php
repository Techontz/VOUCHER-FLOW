<?php

use App\Support\Erp\BusinessConfig;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The ERP foundation: what kind of business a tenant is, which modules it
 * runs, and the roles it defines for itself.
 *
 * A company row carries the configuration rather than a table per setting,
 * because the setup wizard writes it in one step and every module reads it
 * through {@see BusinessConfig}, never the raw JSON.
 *
 * company_roles lets a tenant rename a built-in role's permissions or define a
 * role of its own. A built-in role with no row here keeps the platform default.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('companies', function (Blueprint $table) {
            $table->string('business_type', 40)->default('general')->after('status');
            $table->json('modules')->nullable()->after('business_type');
            $table->json('erp_settings')->nullable()->after('modules');
            $table->timestamp('setup_completed_at')->nullable()->after('erp_settings');
        });

        Schema::create('company_roles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('key', 32);
            $table->string('name', 80);
            $table->string('description', 255)->nullable();
            $table->json('permissions');
            $table->boolean('is_system')->default(false);
            $table->timestamps();

            $table->unique(['company_id', 'key']);
        });

        // Numbering for every ERP document (GRN-2026-000001, JE-2026-000001 …).
        // One locked row per company, key and year.
        Schema::create('document_sequences', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('key', 20);
            $table->unsignedSmallInteger('year');
            $table->unsignedInteger('next_number')->default(1);
            $table->timestamps();

            $table->unique(['company_id', 'key', 'year']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('document_sequences');
        Schema::dropIfExists('company_roles');

        Schema::table('companies', function (Blueprint $table) {
            $table->dropColumn(['business_type', 'modules', 'erp_settings', 'setup_completed_at']);
        });
    }
};
