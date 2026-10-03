<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Adds `pending` — "awaiting platform approval" — to the company lifecycle.
 *
 * A company that registers itself now waits for the platform's super admin
 * before it can use the product. Existing companies keep their status; only
 * the set of allowed values grows, and the column default stays `trial`.
 *
 * MySQL/MariaDB only: the column is a native ENUM there. Other drivers (the
 * SQLite some developers run locally) store it as a string and need nothing.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! in_array(DB::getDriverName(), ['mysql', 'mariadb'], true)) {
            return;
        }

        DB::statement("ALTER TABLE companies MODIFY status ENUM('pending','trial','active','past_due','suspended','cancelled') NOT NULL DEFAULT 'trial'");
    }

    public function down(): void
    {
        if (! in_array(DB::getDriverName(), ['mysql', 'mariadb'], true)) {
            return;
        }

        // A pending company cannot survive the narrower column; it falls back
        // to the state self-registration used to give it.
        DB::table('companies')->where('status', 'pending')->update(['status' => 'trial']);

        DB::statement("ALTER TABLE companies MODIFY status ENUM('trial','active','past_due','suspended','cancelled') NOT NULL DEFAULT 'trial'");
    }
};
