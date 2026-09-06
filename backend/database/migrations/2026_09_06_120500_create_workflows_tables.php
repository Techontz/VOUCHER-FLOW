<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // A workflow is a per-tenant, ordered list of approval steps. Nothing about
        // the HOD -> Manager route is hard-coded: every company defines its own.
        Schema::create('workflows', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('description')->nullable();

            // NULL voucher_type_id = applies to every voucher type not otherwise matched.
            $table->foreignId('voucher_type_id')->nullable()->constrained()->nullOnDelete();

            $table->boolean('is_default')->default(false);
            $table->boolean('is_active')->default(true);
            $table->unsignedInteger('version')->default(1);
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['company_id', 'is_active']);
        });

        Schema::create('workflow_steps', function (Blueprint $table) {
            $table->id();
            $table->foreignId('workflow_id')->constrained()->cascadeOnDelete();
            $table->unsignedSmallInteger('position');
            $table->string('name');
            $table->string('name_sw')->nullable();

            $table->enum('role', ['employee', 'hod', 'manager', 'finance', 'director', 'custom'])->default('manager');
            $table->foreignId('assigned_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('assignee_hint')->nullable();

            // Per-step permissions. A step that only signs cannot approve, which is
            // what makes "HOD signs but does not approve" configuration, not code.
            $table->boolean('can_sign')->default(false);
            $table->boolean('can_approve')->default(false);
            $table->boolean('can_reject')->default(false);
            $table->boolean('can_request_changes')->default(false);
            $table->boolean('can_print')->default(true);
            $table->boolean('can_download')->default(true);
            $table->boolean('requires_signature')->default(false);

            // Optional amount routing: a step can be skipped outside its band.
            $table->decimal('min_amount', 18, 2)->nullable();
            $table->decimal('max_amount', 18, 2)->nullable();

            $table->timestamps();

            $table->unique(['workflow_id', 'position']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('workflow_steps');
        Schema::dropIfExists('workflows');
    }
};
