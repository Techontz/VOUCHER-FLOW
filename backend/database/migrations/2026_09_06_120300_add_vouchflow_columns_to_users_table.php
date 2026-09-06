<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // A NULL company_id marks a platform-level user (super admin). Every
            // other user is permanently bound to exactly one tenant.
            $table->foreignId('company_id')->nullable()->after('id')->constrained()->cascadeOnDelete();
            $table->foreignId('department_id')->nullable()->after('company_id')->constrained('departments')->nullOnDelete();

            $table->enum('role', [
                'super_admin', 'company_admin', 'employee', 'hod', 'manager', 'finance', 'director',
            ])->default('employee')->after('email');

            $table->string('employee_code')->nullable()->after('role');
            $table->string('job_title')->nullable()->after('employee_code');
            $table->string('phone')->nullable()->after('job_title');
            $table->enum('status', ['active', 'invited', 'suspended'])->default('active')->after('phone');

            $table->string('locale', 5)->default('en')->after('status');
            $table->string('theme', 10)->default('dark')->after('locale');
            $table->string('avatar_path')->nullable()->after('theme');

            // Saved signature, reused when the user signs a voucher.
            $table->longText('signature_data')->nullable()->after('avatar_path');
            $table->timestamp('signature_updated_at')->nullable()->after('signature_data');

            $table->boolean('two_factor_enabled')->default(false)->after('signature_updated_at');
            $table->timestamp('last_login_at')->nullable()->after('two_factor_enabled');
            $table->string('last_login_ip', 45)->nullable()->after('last_login_at');
            $table->timestamp('invited_at')->nullable()->after('last_login_ip');
            $table->string('invitation_token', 64)->nullable()->unique()->after('invited_at');

            $table->softDeletes();

            $table->index(['company_id', 'role']);
            $table->index(['company_id', 'status']);
        });

        // Email is unique per tenant, not globally: the same person may hold an
        // account in two different companies.
        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique('users_email_unique');
            $table->unique(['company_id', 'email']);
        });

        // Now that users exists in its final shape, close the departments cycle.
        Schema::table('departments', function (Blueprint $table) {
            $table->foreign('hod_user_id')->references('id')->on('users')->nullOnDelete();
            $table->foreign('manager_user_id')->references('id')->on('users')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('departments', function (Blueprint $table) {
            $table->dropForeign(['hod_user_id']);
            $table->dropForeign(['manager_user_id']);
        });

        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique(['company_id', 'email']);
            $table->dropForeign(['company_id']);
            $table->dropForeign(['department_id']);
            $table->dropColumn([
                'company_id', 'department_id', 'role', 'employee_code', 'job_title', 'phone',
                'status', 'locale', 'theme', 'avatar_path', 'signature_data', 'signature_updated_at',
                'two_factor_enabled', 'last_login_at', 'last_login_ip', 'invited_at',
                'invitation_token', 'deleted_at',
            ]);
            $table->unique('email');
        });
    }
};
