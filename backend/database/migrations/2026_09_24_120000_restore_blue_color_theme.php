<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Back to blue as the default interface colour.
 *
 * A short-lived crimson default was withdrawn along with the design it came
 * with, and the app no longer offers crimson, so any company left on it moves
 * back to blue. On a database that never had crimson this changes nothing.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE companies MODIFY color_theme VARCHAR(20) NOT NULL DEFAULT 'blue'");

        DB::table('companies')->where('color_theme', 'crimson')->update(['color_theme' => 'blue']);
    }

    public function down(): void
    {
        // Nothing to undo: crimson is no longer a valid colour.
    }
};
