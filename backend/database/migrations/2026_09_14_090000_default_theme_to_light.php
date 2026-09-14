<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Light is the product's default appearance again; dark is a preference.
 *
 * The column default moves back to 'light', and existing rows still holding
 * 'dark' move with it. Those values are not a record of anyone's choice: the
 * previous migration made 'dark' the default every account was created with,
 * and theme changes were never recorded separately, so a stored 'dark' cannot
 * be told apart from "never touched". Anyone who does prefer dark switches
 * back with one click, and that choice is saved to their profile as before.
 *
 * Nothing else about users or companies is read or written.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE users MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'light'");
        DB::statement("ALTER TABLE companies MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'light'");

        DB::table('users')->where('theme', 'dark')->update(['theme' => 'light']);
        DB::table('companies')->where('theme', 'dark')->update(['theme' => 'light']);
    }

    public function down(): void
    {
        // The default can be restored; which accounts were dark before cannot.
        DB::statement("ALTER TABLE users MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'dark'");
        DB::statement("ALTER TABLE companies MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'dark'");
    }
};
