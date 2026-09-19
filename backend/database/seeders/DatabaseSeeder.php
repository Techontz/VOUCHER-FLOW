<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call(PlanSeeder::class);

        $this->seedPlatformOperator();

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

    /**
     * The platform operator. Not attached to any company, so the tenant scope
     * lifts for this account alone.
     *
     * Created once and never overwritten: db:seed is re-run on deploys to pick
     * up new plans, and it must not reset a password the operator has since
     * changed. Outside local work there is no default password — without
     * SUPER_ADMIN_PASSWORD the account is skipped, not created guessable.
     */
    private function seedPlatformOperator(): void
    {
        $email = config('vouchflow.super_admin.email');

        $existing = User::withoutGlobalScopes()
            ->whereNull('company_id')
            ->where('email', $email)
            ->exists();

        if ($existing) {
            return;
        }

        $password = config('vouchflow.super_admin.password')
            ?? (app()->environment('local', 'testing') ? 'Password123!' : null);

        if ($password === null) {
            $this->command?->warn(
                "Platform operator {$email} not created: set SUPER_ADMIN_PASSWORD, run "
                .'php artisan config:cache, then db:seed again.'
            );

            return;
        }

        User::create([
            'email' => $email,
            'company_id' => null,
            'name' => 'Platform Operator',
            'password' => $password,
            'role' => User::ROLE_SUPER_ADMIN,
            'status' => 'active',
            'job_title' => 'Platform Super Admin',
            'email_verified_at' => now(),
        ]);
    }
}
