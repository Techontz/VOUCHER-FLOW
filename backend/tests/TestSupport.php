<?php

namespace Tests;

use App\Models\Company;
use App\Models\Department;
use App\Models\Erp\Product;
use App\Models\Erp\Supplier;
use App\Models\Erp\Unit;
use App\Models\Erp\Warehouse;
use App\Models\Plan;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherType;
use App\Services\AmountFormatter;
use App\Services\CompanyProvisioner;
use App\Services\Erp\BusinessSetup;
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
     * @return array{company:Company,admin:User,employee:User,hod:User,ceo:User,cashier:User,manager:User,finance:User,department:Department}
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
            // The default route approves at a CEO step and pays at a cashier
            // step; manager and finance stay for the presets that use them.
            $ceo = $make('ceo', User::ROLE_CEO);
            $cashier = $make('cashier', User::ROLE_CASHIER);
            $manager = $make('manager', User::ROLE_MANAGER);
            $finance = $make('finance', User::ROLE_FINANCE);

            $department = Department::create([
                'company_id' => $company->id,
                'name' => 'Operations',
                'hod_user_id' => $hod->id,
                'manager_user_id' => $manager->id,
            ]);

            $employee->update(['department_id' => $department->id]);

            return compact('company', 'admin', 'employee', 'hod', 'ceo', 'cashier', 'manager', 'finance', 'department');
        });
    }

    /**
     * Runs the business setup for a tenant and adds the ERP people and things
     * most tests need: a storekeeper, a warehouse manager, an accountant, two
     * warehouses, a supplier and a carton product.
     *
     * @return array<string, mixed>
     */
    protected function setUpErp(array $tenant, string $type = 'wholesale', array $settings = []): array
    {
        $company = $tenant['company'];

        app(BusinessSetup::class)->apply($company, $type, null, $settings, $tenant['admin']);

        return app(TenantContext::class)->forCompany($company->fresh(), function () use ($tenant, $company) {
            $slug = $company->slug;
            $make = fn (string $key, string $role) => User::create([
                'company_id' => $company->id, 'name' => ucfirst($key)." {$slug}",
                'email' => "{$key}@{$slug}.test", 'password' => 'Password123!', 'role' => $role, 'status' => 'active',
            ]);

            $carton = Unit::where('code', 'CTN')->first() ?? Unit::create(['company_id' => $company->id, 'code' => 'CTN', 'name' => 'Carton']);

            return [
                ...$tenant,
                'company' => $company->fresh(),
                'storekeeper' => $make('storekeeper', User::ROLE_STOREKEEPER),
                'warehouse_manager' => $make('warehousemgr', User::ROLE_WAREHOUSE_MANAGER),
                'accountant' => $make('accountant', User::ROLE_ACCOUNTANT),
                'main' => Warehouse::where('code', 'MAIN')->firstOrFail(),
                'depot' => Warehouse::create(['company_id' => $company->id, 'code' => 'DEP', 'name' => 'Depot']),
                'supplier' => Supplier::create(['company_id' => $company->id, 'code' => 'SUP-1', 'name' => 'Kilimo Supplies']),
                'product' => Product::create([
                    'company_id' => $company->id, 'sku' => 'WTR-500', 'name' => 'Water 500ml x24',
                    'unit_id' => $carton->id, 'cost_price' => 6000, 'sale_price' => 9000, 'reorder_level' => 10,
                ]),
            ];
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
