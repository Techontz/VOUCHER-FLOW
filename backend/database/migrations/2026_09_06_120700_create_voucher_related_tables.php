<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // The approval timeline: one immutable row per action taken on a voucher.
        Schema::create('voucher_approvals', function (Blueprint $table) {
            $table->id();
            $table->foreignId('voucher_id')->constrained()->cascadeOnDelete();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('workflow_step_id')->nullable()->constrained()->nullOnDelete();

            $table->unsignedSmallInteger('step_position')->nullable();
            $table->string('step_name')->nullable();
            $table->string('step_role')->nullable();

            $table->foreignId('actor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('actor_name');
            $table->string('actor_role')->nullable();

            $table->enum('action', [
                'created', 'submitted', 'signed', 'approved', 'rejected',
                'changes_requested', 'resubmitted', 'forwarded', 'cancelled',
            ]);

            $table->text('comment')->nullable();
            $table->longText('signature_data')->nullable();
            $table->string('ip', 45)->nullable();
            $table->string('user_agent')->nullable();
            $table->timestamp('acted_at');
            $table->timestamps();

            $table->index(['voucher_id', 'acted_at']);
            $table->index(['company_id', 'action']);
        });

        Schema::create('voucher_attachments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('voucher_id')->constrained()->cascadeOnDelete();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('uploaded_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('original_name');
            $table->string('path');
            $table->string('disk', 30)->default('local');
            $table->string('mime_type', 120)->nullable();
            $table->unsignedBigInteger('size_bytes')->default(0);
            $table->timestamps();

            $table->index(['company_id']);
        });

        Schema::create('voucher_comments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('voucher_id')->constrained()->cascadeOnDelete();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->text('body');
            $table->timestamps();

            $table->index(['voucher_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('voucher_comments');
        Schema::dropIfExists('voucher_attachments');
        Schema::dropIfExists('voucher_approvals');
    }
};
