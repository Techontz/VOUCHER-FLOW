<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Two things the first tenant exposed.
 *
 * 1. Roles lived in a MySQL enum, which quietly made the role vocabulary a
 *    property of the schema rather than of the product. A tenant that calls its
 *    approver a Supervisor could not be represented without a migration, and the
 *    brief is explicit that roles are configurable per company. The column
 *    becomes a short string; the permitted values now live on the models, which
 *    is where a company-specific list can eventually be read from.
 *
 * 2. A workflow step could be told to sign, approve, reject, request changes,
 *    print and download — but not to pay. Releasing money was inferred from the
 *    role instead, which is the one capability a company cannot reassign. It
 *    joins the others as a flag.
 */
return new class extends Migration
{
    public function up(): void
    {
        // MySQL needs the enum rewritten rather than modified in place.
        DB::statement("ALTER TABLE users MODIFY role VARCHAR(32) NOT NULL DEFAULT 'employee'");
        DB::statement("ALTER TABLE workflow_steps MODIFY role VARCHAR(32) NOT NULL DEFAULT 'manager'");

        Schema::table('workflow_steps', function (Blueprint $table) {
            $table->boolean('can_pay')->default(false)->after('can_download');
        });

        // Whoever was already releasing money keeps doing so: the final step of
        // each workflow, which is what the payment queue was reading before.
        DB::statement("
            UPDATE workflow_steps s
            JOIN (SELECT workflow_id, MAX(position) AS last_position FROM workflow_steps GROUP BY workflow_id) t
              ON t.workflow_id = s.workflow_id AND t.last_position = s.position
            SET s.can_pay = 1
            WHERE s.role IN ('finance', 'cashier')
        ");
    }

    public function down(): void
    {
        Schema::table('workflow_steps', function (Blueprint $table) {
            $table->dropColumn('can_pay');
        });

        DB::statement("UPDATE users SET role = 'manager' WHERE role IN ('ceo')");
        DB::statement("UPDATE users SET role = 'finance' WHERE role IN ('cashier')");
        DB::statement("ALTER TABLE users MODIFY role ENUM('super_admin','company_admin','employee','hod','manager','finance','director') NOT NULL DEFAULT 'employee'");
        DB::statement("ALTER TABLE workflow_steps MODIFY role ENUM('employee','hod','manager','finance','director','custom') NOT NULL DEFAULT 'manager'");
    }
};
