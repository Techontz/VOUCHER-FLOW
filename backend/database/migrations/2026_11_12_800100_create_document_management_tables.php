<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Document management: nested folders, documents with every version kept on
 * the private disk, links to any record, and a trail of who opened what.
 *
 * Access is stored on both folders and documents as a scope ('company',
 * 'roles', 'users'; documents also 'inherit') with the role keys or user ids
 * it names. Links are polymorphic by type string and id, with no foreign key,
 * so a document can point at a vehicle or an employee from another module.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('dms_folders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('parent_id')->nullable()->constrained('dms_folders')->cascadeOnDelete();
            $table->string('name', 120);
            $table->string('description', 255)->nullable();
            $table->string('access_scope', 20)->default('company');
            $table->json('access_roles')->nullable();
            $table->json('access_users')->nullable();
            $table->unsignedSmallInteger('retention_years')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'parent_id', 'name']);
        });

        Schema::create('dms_documents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('folder_id')->nullable()->constrained('dms_folders')->nullOnDelete();
            $table->string('title', 180);
            $table->string('document_type', 40)->default('general');
            $table->json('tags')->nullable();
            $table->text('description')->nullable();
            $table->string('reference', 80)->nullable();
            $table->date('issued_on')->nullable();
            $table->date('expires_on')->nullable();
            $table->string('access_scope', 20)->default('inherit');
            $table->json('access_roles')->nullable();
            $table->json('access_users')->nullable();
            $table->unsignedSmallInteger('retention_years')->nullable();
            $table->date('retain_until')->nullable();
            $table->unsignedInteger('current_version')->default(1);
            $table->foreignId('owner_id')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('deleted_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['company_id', 'folder_id']);
            $table->index(['company_id', 'expires_on']);
        });

        Schema::create('dms_document_versions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('document_id')->constrained('dms_documents')->cascadeOnDelete();
            $table->unsignedInteger('version');
            $table->string('disk', 20)->default('local');
            $table->string('path', 255);
            $table->string('original_name', 255);
            $table->string('mime_type', 120)->nullable();
            $table->unsignedBigInteger('size_bytes')->default(0);
            $table->string('checksum', 64)->nullable();
            $table->string('note', 255)->nullable();
            $table->foreignId('uploaded_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['document_id', 'version']);
        });

        Schema::create('dms_document_links', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('document_id')->constrained('dms_documents')->cascadeOnDelete();
            $table->string('attachable_type', 40);
            $table->unsignedBigInteger('attachable_id');
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['document_id', 'attachable_type', 'attachable_id'], 'dms_links_unique');
            $table->index(['company_id', 'attachable_type', 'attachable_id'], 'dms_links_record');
        });

        Schema::create('dms_access_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('document_id')->constrained('dms_documents')->cascadeOnDelete();
            $table->unsignedInteger('version')->nullable();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('action', 20);
            $table->string('ip', 45)->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['document_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('dms_access_logs');
        Schema::dropIfExists('dms_document_links');
        Schema::dropIfExists('dms_document_versions');
        Schema::dropIfExists('dms_documents');
        Schema::dropIfExists('dms_folders');
    }
};
