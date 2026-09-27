<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The preset's signing step was called "Department review", which read as if
 * the head of department decided the voucher. It signs only, so it is now
 * "HOD signature". Only steps still carrying the untouched preset name and no
 * approval power are renamed — anything a company admin renamed is theirs.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('workflow_steps')
            ->where('name', 'Department review')
            ->where('can_approve', false)
            ->update(['name' => 'HOD signature']);

        DB::table('workflow_steps')
            ->where('name', 'HOD signature')
            ->where('can_approve', false)
            ->where(fn ($q) => $q->whereNull('name_sw')->orWhere('name_sw', 'Ukaguzi wa idara'))
            ->update(['name_sw' => 'Sahihi ya Mkuu wa Idara']);
    }

    public function down(): void
    {
        DB::table('workflow_steps')
            ->where('name', 'HOD signature')
            ->where('can_approve', false)
            ->update(['name' => 'Department review', 'name_sw' => 'Ukaguzi wa idara']);
    }
};
