<?php

namespace Database\Seeders;

use App\Models\Plan;
use Illuminate\Database\Seeder;

class PlanSeeder extends Seeder
{
    /** The basic tier: payment vouchers and the core of a trading business. */
    public const STARTER_APPS = ['vouchflow', 'inventory', 'sales', 'procurement', 'accounting'];

    /** The middle tier adds making, moving and the people who do it. */
    public const BUSINESS_APPS = [...self::STARTER_APPS, 'production', 'dispatch', 'fleet', 'hr', 'documents'];

    public const PREMIUM_APPS = [...self::BUSINESS_APPS, 'crm'];

    /**
     * Plans are tiers by the number of apps: Starter has five, Business ten,
     * Premium eleven and Enterprise every app (no list, so apps added later
     * are included too). Each also offers a pick-your-apps plan's machinery
     * (allows_module_choice), which the platform can switch on from the plans
     * editor; none of the seeded plans uses it.
     */
    public function run(): void
    {
        $plans = [
            [
                'code' => 'starter',
                'name' => 'Starter',
                'blurb' => '5 apps: vouchers, inventory, sales, procurement and accounting. Up to 10 users.',
                'blurb_sw' => 'Programu 5: vocha, stoo, mauzo, ununuzi na uhasibu. Hadi watumiaji 10.',
                'price' => 79000,
                'billing_cycle' => 'monthly',
                'max_users' => 10,
                'max_vouchers_per_month' => 100,
                'max_departments' => 5,
                'max_approval_levels' => 2,
                'storage_mb' => 2048,
                'trial_days' => 14,
                'features' => ['5 apps', '10 users', '100 vouchers / month', '2 approval levels', 'PDF vouchers', 'Email support'],
                'modules' => self::STARTER_APPS,
                'sort_order' => 1,
            ],
            [
                'code' => 'business',
                'name' => 'Business',
                'blurb' => '10 apps, adding production, dispatch, fleet, HR and documents.',
                'blurb_sw' => 'Programu 10, zikiongeza uzalishaji, usambazaji, magari, rasilimali watu na nyaraka.',
                'price' => 249000,
                'billing_cycle' => 'monthly',
                'max_users' => 50,
                'max_vouchers_per_month' => null,
                'max_departments' => 20,
                'max_approval_levels' => 3,
                'storage_mb' => 25600,
                'trial_days' => 14,
                'features' => ['10 apps', '50 users', 'Unlimited vouchers', '3 approval levels', 'Custom branding', 'Reports & exports', 'Priority support'],
                'modules' => self::BUSINESS_APPS,
                'sort_order' => 2,
            ],
            [
                'code' => 'premium',
                'name' => 'Premium',
                'blurb' => '11 apps, adding CRM, with deeper workflows for larger teams.',
                'blurb_sw' => 'Programu 11, ikiongeza CRM, na mitiririko mipana kwa timu kubwa.',
                'price' => 590000,
                'billing_cycle' => 'monthly',
                'max_users' => 150,
                'max_vouchers_per_month' => null,
                'max_departments' => 60,
                'max_approval_levels' => 6,
                'storage_mb' => 102400,
                'trial_days' => 14,
                'features' => ['11 apps', '150 users', 'Unlimited vouchers', '6 approval levels', 'Custom branding', 'Advanced reports', 'Priority support'],
                'modules' => self::PREMIUM_APPS,
                'sort_order' => 3,
            ],
            [
                'code' => 'enterprise',
                'name' => 'Enterprise',
                'blurb' => 'All apps, multiple companies, custom workflows, integrations.',
                'blurb_sw' => 'Programu zote, kampuni nyingi, mitiririko maalum, miunganisho.',
                'price' => 0,
                'billing_cycle' => 'annual',
                'max_users' => null,
                'max_vouchers_per_month' => null,
                'max_departments' => null,
                'max_approval_levels' => null,
                'storage_mb' => null,
                'trial_days' => 30,
                'features' => ['All apps', 'Unlimited users', 'Custom workflows', 'Multi-company', 'API & integrations', 'Dedicated manager'],
                'modules' => null,
                'sort_order' => 4,
            ],
        ];

        foreach ($plans as $plan) {
            Plan::updateOrCreate(['code' => $plan['code']], $plan + ['currency' => 'TZS', 'is_active' => true, 'is_public' => true]);
        }
    }
}
