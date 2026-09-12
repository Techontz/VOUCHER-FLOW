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

        // Demo tenants are opt-in, and off unless asked for. `db:seed` on a
        // production box must give you the plans and the platform operator and
        // nothing else. .env.example carries SEED_DEMO=true so local work still
        // gets the demo world by default.
        //
        // Read from config, not env(): production caches its config, and with
        // the config cached env() no longer sees .env. See config/vouchflow.php.
        //
        // DemoSeeder can always be run directly and deliberately:
        //   php artisan db:seed --class=DemoSeeder --force
        if (config('vouchflow.seed_demo')) {
            $this->call(DemoSeeder::class);
        }
    }
}
