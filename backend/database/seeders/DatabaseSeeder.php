<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call(PlanSeeder::class);

        // The platform operator. Not attached to any company, so the tenant scope
        // lifts for this account alone.
        User::updateOrCreate(
            ['email' => env('SUPER_ADMIN_EMAIL', 'super@vouchflow.test')],
            [
                'company_id' => null,
                'name' => 'Platform Operator',
                'password' => env('SUPER_ADMIN_PASSWORD', 'Password123!'),
                'role' => User::ROLE_SUPER_ADMIN,
                'status' => 'active',
                'job_title' => 'Platform Super Admin',
                'email_verified_at' => now(),
            ],
        );

        if (filter_var(env('SEED_DEMO', true), FILTER_VALIDATE_BOOL)) {
            $this->call(DemoSeeder::class);
        }
    }
}
