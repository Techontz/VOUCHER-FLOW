<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Dark is the product's default appearance.
 *
 * Only the column DEFAULT moves, so accounts that already exist keep whatever
 * they chose. Light stays a first-class option — it is simply no longer what a
 * new account starts on.
 */
return new class extends Migration
{
    public function up(): void
    {
        // Raw DDL rather than doctrine/dbal: the column type is unchanged, only
        // the default it hands to new rows.
        DB::statement("ALTER TABLE users MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'dark'");
        DB::statement("ALTER TABLE companies MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'dark'");
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE users MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'light'");
        DB::statement("ALTER TABLE companies MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'light'");
    }
};
