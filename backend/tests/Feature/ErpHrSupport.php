<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Testing\TestResponse;

/**
 * Builds an HR-enabled tenant for the HR tests: the ERP setup with HR and
 * accounting switched on, an HR manager, and helpers that hire people through
 * the API the screens use.
 */
trait ErpHrSupport
{
    /** @return array<string, mixed> */
    protected function setUpHr(string $name = 'Maji Bora'): array
    {
        $erp = $this->setUpErp($this->makeTenant($name), 'wholesale');
        $company = $erp['company'];
        $company->forceFill(['modules' => array_values(array_unique([...(array) $company->modules, 'hr', 'accounting']))])->save();

        return app(TenantContext::class)->forCompany($company->fresh(), function () use ($erp, $company) {
            $slug = $company->slug;

            return [
                ...$erp,
                'company' => $company->fresh(),
                'hr' => User::create([
                    'company_id' => $company->id, 'name' => "HR {$slug}", 'email' => "hr@{$slug}.test",
                    'password' => 'Password123!', 'role' => User::ROLE_HR_MANAGER, 'status' => 'active',
                ]),
            ];
        });
    }

    /** @param  array<string, mixed>  $overrides */
    protected function hire(array $hr, array $overrides = [], ?array $contract = null): TestResponse
    {
        return $this->actingAs($hr['hr'], 'sanctum')->postJson('/api/erp/hr/employees', [
            'full_name' => 'Asha Mwakyusa',
            'employment_type' => 'permanent',
            'hire_date' => '2025-01-01',
            'department_id' => $hr['department']->id,
            'job_title' => 'Machine operator',
            ...$overrides,
            'contract' => $contract ?? [
                'type' => 'permanent', 'start_date' => '2025-01-01', 'basic_salary' => 800000,
                'housing_allowance' => 0, 'transport_allowance' => 0, 'other_allowance' => 0,
            ],
        ]);
    }

    protected function lastMonth(): string
    {
        return now()->startOfMonth()->subMonth()->format('Y-m');
    }
}
