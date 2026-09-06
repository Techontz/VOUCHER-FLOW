<?php

namespace Tests;

use App\Models\Company;
use App\Models\Department;
use App\Models\Plan;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherType;
use App\Services\AmountFormatter;
use App\Services\CompanyProvisioner;
use App\Services\VoucherNumberGenerator;
use App\Services\WorkflowEngine;
use App\Support\TenantContext;
use Database\Seeders\PlanSeeder;

/**
 * Builds a self-contained tenant for a test: company, people, departments and a
 * workflow, all created through the real provisioning path.
 */
trait TestSupport
{
    protected function seedPlans(): void
    {
        if (Plan::count() === 0) {
            $this->seed(PlanSeeder::class);
        }
    }

    /**
     * @return array{company:Company,admin:User,employee:User,hod:User,manager:User,department:Department}
     */
    protected function makeTenant(string $name, string $preset = 'default'): array
    {
        $this->seedPlans();

        $tenant = app(TenantContext::class);
        $slug = str($name)->slug()->toString();

        ['company' => $company, 'admin' => $admin] = app(CompanyProvisioner::class)->provision(
            ['name' => $name, 'email' => "accounts@{$slug}.test"],
            ['name' => "{$name} Admin", 'email' => "admin@{$slug}.test", 'password' => 'Password123!'],
            Plan::where('code', 'business')->first(),
        );

        return $tenant->forCompany($company, function () use ($company, $admin, $slug, $preset) {
            $company->forceFill(['status' => 'active'])->save();

            if ($preset !== 'default') {
                app(CompanyProvisioner::class)->applyPreset($company, $preset, $admin);
            }

            $make = fn (string $key, string $role) => User::create([
                'company_id' => $company->id,
                'name' => ucfirst($key)." {$slug}",
                'email' => "{$key}@{$slug}.test",
                'password' => 'Password123!',
                'role' => $role,
                'status' => 'active',
            ]);

            $employee = $make('employee', User::ROLE_EMPLOYEE);
            $hod = $make('hod', User::ROLE_HOD);
            $manager = $make('manager', User::ROLE_MANAGER);
            $finance = $make('finance', User::ROLE_FINANCE);

            $department = Department::create([
                'company_id' => $company->id,
                'name' => 'Operations',
                'hod_user_id' => $hod->id,
                'manager_user_id' => $manager->id,
            ]);

            $employee->update(['department_id' => $department->id]);

            return compact('company', 'admin', 'employee', 'hod', 'manager', 'finance', 'department');
        });
    }

    /** Creates a draft voucher owned by the given requester. */
    protected function makeVoucher(array $tenant, ?User $requester = null, float $amount = 250000): Voucher
    {
        $company = $tenant['company'];
        $requester ??= $tenant['employee'];

        return app(TenantContext::class)->forCompany($company, function () use ($company, $requester, $tenant, $amount) {
            $type = VoucherType::where('code', 'payment')->firstOrFail();
            $engine = app(WorkflowEngine::class);

            return Voucher::create([
                'company_id' => $company->id,
                'number' => app(VoucherNumberGenerator::class)->next($type),
                'voucher_type_id' => $type->id,
                'workflow_id' => $engine->resolveWorkflow($type)?->id,
                'department_id' => $tenant['department']->id,
                'requester_id' => $requester->id,
                'payee' => 'Test Supplier Ltd',
                'purpose' => 'Test purchase',
                'amount' => $amount,
                'currency' => 'TZS',
                'amount_in_words' => app(AmountFormatter::class)->inWords($amount, 'TZS'),
                'payment_method' => 'Bank Transfer',
                'voucher_date' => now()->toDateString(),
                'status' => Voucher::STATUS_DRAFT,
                'verification_code' => app(VoucherNumberGenerator::class)->verificationCode(),
                'created_by' => $requester->id,
            ]);
        });
    }
}
