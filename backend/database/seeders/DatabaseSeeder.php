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

        // Demo tenants are for local work and demonstrations. The default
        // follows the environment rather than being `true` everywhere: a
        // production deploy that runs db:seed should get the plans and the
        // platform operator, and NOT three fictional companies. Setting
        // SEED_DEMO=true explicitly still opts in anywhere.
        $demoByDefault = app()->environment(['local', 'testing', 'development']);

        if (filter_var(env('SEED_DEMO', $demoByDefault), FILTER_VALIDATE_BOOL)) {
            $this->call(DemoSeeder::class);
        }
    }
}
