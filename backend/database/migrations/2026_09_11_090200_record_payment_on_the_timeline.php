<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The timeline could record every act except the one the voucher exists for.
 * Releasing the money is an event with an actor, a time and a signature, and it
 * belongs on the same audit trail as the approval that authorised it.
 */
return new class extends Migration
{
    private const ACTIONS = "'created','submitted','signed','approved','rejected','changes_requested','resubmitted','forwarded','cancelled','paid'";

    public function up(): void
    {
        DB::statement('ALTER TABLE voucher_approvals MODIFY action ENUM('.self::ACTIONS.') NOT NULL');
    }

    public function down(): void
    {
        DB::statement("DELETE FROM voucher_approvals WHERE action = 'paid'");
        DB::statement("ALTER TABLE voucher_approvals MODIFY action ENUM('created','submitted','signed','approved','rejected','changes_requested','resubmitted','forwarded','cancelled') NOT NULL");
    }
};
