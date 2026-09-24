<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Crimson is VouchFlow's own interface colour and the default for every company.
 *
 * The column default moves to 'crimson', and rows still holding 'blue' move
 * with it. Those values are the previous default: color_theme was added days
 * ago with 'blue' filled in for everyone, and a stored 'blue' cannot be told
 * apart from "never chosen". A company that picked emerald, violet or rose
 * keeps its choice; one that wants blue picks it again under Branding.
 *
 * Nothing else about companies is read or written.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE companies MODIFY color_theme VARCHAR(20) NOT NULL DEFAULT 'crimson'");

        DB::table('companies')->where('color_theme', 'blue')->update(['color_theme' => 'crimson']);
    }

    public function down(): void
    {
        // The default can be restored; which companies chose blue cannot.
        DB::statement("ALTER TABLE companies MODIFY color_theme VARCHAR(20) NOT NULL DEFAULT 'blue'");

        DB::table('companies')->where('color_theme', 'crimson')->update(['color_theme' => 'blue']);
    }
};
