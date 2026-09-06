<?php

namespace Database\Seeders;

use App\Models\Plan;
use Illuminate\Database\Seeder;

class PlanSeeder extends Seeder
{
    public function run(): void
    {
        $plans = [
            [
                'code' => 'starter',
                'name' => 'Starter',
                'blurb' => 'Up to 10 users and 100 vouchers a month.',
                'blurb_sw' => 'Hadi watumiaji 10 na vocha 100 kwa mwezi.',
                'price' => 79000,
                'billing_cycle' => 'monthly',
                'max_users' => 10,
                'max_vouchers_per_month' => 100,
                'max_departments' => 5,
                'max_approval_levels' => 2,
                'storage_mb' => 2048,
                'trial_days' => 14,
                'features' => ['10 users', '100 vouchers / month', '2 approval levels', 'PDF vouchers', 'Email support'],
                'sort_order' => 1,
            ],
            [
                'code' => 'business',
                'name' => 'Business',
                'blurb' => 'Departments, branding and reporting for growing companies.',
                'blurb_sw' => 'Idara, chapa na ripoti kwa kampuni zinazokua.',
                'price' => 249000,
                'billing_cycle' => 'monthly',
                'max_users' => 50,
                'max_vouchers_per_month' => null,
                'max_departments' => 20,
                'max_approval_levels' => 3,
                'storage_mb' => 25600,
                'trial_days' => 14,
                'features' => ['50 users', 'Unlimited vouchers', '3 approval levels', 'Custom branding', 'Reports & exports', 'Priority support'],
                'sort_order' => 2,
            ],
            [
                'code' => 'premium',
                'name' => 'Premium',
                'blurb' => 'Deeper workflows and more room for larger finance teams.',
                'blurb_sw' => 'Mitiririko mipana na nafasi zaidi kwa timu kubwa za fedha.',
                'price' => 590000,
                'billing_cycle' => 'monthly',
                'max_users' => 150,
                'max_vouchers_per_month' => null,
                'max_departments' => 60,
                'max_approval_levels' => 6,
                'storage_mb' => 102400,
                'trial_days' => 14,
                'features' => ['150 users', 'Unlimited vouchers', '6 approval levels', 'Custom branding', 'Advanced reports', 'Priority support'],
                'sort_order' => 3,
            ],
            [
                'code' => 'enterprise',
                'name' => 'Enterprise',
                'blurb' => 'Multiple companies, custom workflows, integrations.',
                'blurb_sw' => 'Kampuni nyingi, mitiririko maalum, miunganisho.',
                'price' => 0,
                'billing_cycle' => 'annual',
                'max_users' => null,
                'max_vouchers_per_month' => null,
                'max_departments' => null,
                'max_approval_levels' => null,
                'storage_mb' => null,
                'trial_days' => 30,
                'features' => ['Unlimited users', 'Custom workflows', 'Multi-company', 'API & integrations', 'Dedicated manager'],
                'sort_order' => 4,
            ],
        ];

        foreach ($plans as $plan) {
            Plan::updateOrCreate(['code' => $plan['code']], $plan + ['currency' => 'TZS', 'is_active' => true, 'is_public' => true]);
        }
    }
}
