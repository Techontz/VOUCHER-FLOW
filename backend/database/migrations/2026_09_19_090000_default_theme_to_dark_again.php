<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Dark is the product's default appearance again; light is a preference.
 *
 * The column default moves to 'dark', and existing rows holding 'light' move
 * with it. Those values are almost all the previous migration's doing: it reset
 * every account to 'light', and theme changes are not recorded separately, so a
 * stored 'light' cannot be told apart from "never touched". Anyone who does
 * prefer light switches back with one click, and that choice is saved to their
 * profile as before.
 *
 * Nothing else about users or companies is read or written.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE users MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'dark'");
        DB::statement("ALTER TABLE companies MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'dark'");

        DB::table('users')->where('theme', 'light')->update(['theme' => 'dark']);
        DB::table('companies')->where('theme', 'light')->update(['theme' => 'dark']);
    }

    public function down(): void
    {
        // The default can be restored; which accounts were light before cannot.
        DB::statement("ALTER TABLE users MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'light'");
        DB::statement("ALTER TABLE companies MODIFY theme VARCHAR(10) NOT NULL DEFAULT 'light'");
    }
};
