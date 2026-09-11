<?php

namespace App\Services;

use App\Models\Company;
use App\Models\Department;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherAttachment;
use App\Support\TenantContext;
use RuntimeException;

/**
 * Plan enforcement: seats, monthly voucher volume, departments, approval depth
 * and storage. A NULL limit on the plan means unlimited.
 */
class UsageLimits
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function snapshot(Company $company): array
    {
        $plan = $company->plan;

        return $this->tenant->forCompany($company, function () use ($company, $plan) {
            $users = User::where('company_id', $company->id)->whereNull('deleted_at')->count();
            $vouchersThisMonth = Voucher::whereBetween('created_at', [now()->startOfMonth(), now()->endOfMonth()])->count();
            $departments = Department::count();
            $storageBytes = (int) VoucherAttachment::sum('size_bytes');

            return [
                'plan' => $plan?->name,
                'users' => $this->metric('Users', $users, $plan?->max_users),
                'vouchers_this_month' => $this->metric('Vouchers this month', $vouchersThisMonth, $plan?->max_vouchers_per_month),
                'departments' => $this->metric('Departments', $departments, $plan?->max_departments),
                'storage' => $this->metric(
                    'Storage',
                    (int) round($storageBytes / 1048576),
                    $plan?->storage_mb,
                    'MB',
                ),
                'approval_levels' => [
                    'label' => 'Approval levels',
                    'limit' => $plan?->max_approval_levels,
                ],
            ];
        });
    }

    private function metric(string $label, int $used, ?int $limit, string $unit = ''): array
    {
        return [
            'label' => $label,
            'used' => $used,
            'limit' => $limit,
            'unit' => $unit,
            'unlimited' => $limit === null,
            'percent' => $limit ? min(100, (int) round($used / max($limit, 1) * 100)) : null,
            'exceeded' => $limit !== null && $used >= $limit,
        ];
    }

    public function assertCanAddUser(Company $company): void
    {
        $limit = $company->plan?->max_users;

        if ($limit === null) {
            return;
        }

        $used = User::where('company_id', $company->id)->whereNull('deleted_at')->count();

        if ($used >= $limit) {
            throw new RuntimeException(
                "Your {$company->plan->name} plan allows {$limit} users and {$used} are in use. Upgrade the plan to add more."
            );
        }
    }

    public function assertCanCreateVoucher(Company $company): void
    {
        $limit = $company->plan?->max_vouchers_per_month;

        if ($limit === null) {
            return;
        }

        $used = $this->tenant->forCompany($company, fn () => Voucher::whereBetween('created_at', [now()->startOfMonth(), now()->endOfMonth()])->count());

        if ($used >= $limit) {
            throw new RuntimeException(
                "Your {$company->plan->name} plan allows {$limit} vouchers per month and {$used} have been created. Upgrade the plan to continue."
            );
        }
    }

    public function assertCanAddDepartment(Company $company): void
    {
        $limit = $company->plan?->max_departments;

        if ($limit === null) {
            return;
        }

        $used = $this->tenant->forCompany($company, fn () => Department::count());

        if ($used >= $limit) {
            throw new RuntimeException("Your {$company->plan->name} plan allows {$limit} departments.");
        }
    }

    /**
     * @param  array<int,array<string,mixed>>  $steps  the step definitions being saved
     */
    public function assertApprovalDepth(Company $company, array $steps): void
    {
        $limit = $company->plan?->max_approval_levels;

        // Neither the request step nor a pay-only step is an approval level.
        // A plan sells how many people must agree, not how many hands the
        // voucher passes through, and a cashier decides nothing.
        $levels = 0;

        foreach ($steps as $index => $step) {
            $isRequest = $index === 0 || ($step['role'] ?? null) === 'employee';
            $paysOnly = ($step['can_pay'] ?? false) && ! ($step['can_approve'] ?? false);

            if (! $isRequest && ! $paysOnly) {
                $levels++;
            }
        }

        if ($limit !== null && $levels > $limit) {
            throw new RuntimeException(
                "Your {$company->plan->name} plan allows {$limit} approval levels; this workflow defines {$levels}."
            );
        }
    }

    public function assertUploadSize(int $bytes): void
    {
        $max = (int) config('vouchflow.max_upload_mb', 10) * 1048576;

        if ($bytes > $max) {
            throw new RuntimeException('Attachments may not exceed '.config('vouchflow.max_upload_mb', 10).' MB.');
        }
    }
}
