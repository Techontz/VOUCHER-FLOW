<?php

use App\Models\User;

/*
 * Production & manufacturing: bills of materials, production orders, material
 * issue to work in progress, finished goods receipt behind a quality check,
 * batch genealogy and production costing.
 *
 * Materials leave the store Dr Work in progress / Cr Inventory; released
 * output arrives Dr Inventory / Cr Work in progress at the order's actual
 * cost; labour and overheads are applied Dr Work in progress / Cr the applied
 * accounts below; what is left on work in progress when the order closes is
 * the production variance.
 */

$view = ['production.view'];

return [
    'module' => 'production',
    'permissions' => [
        'production.view' => ['label' => 'View bills of materials, production orders, quality checks and genealogy', 'group' => 'Production'],
        'production.manage' => ['label' => 'Maintain bills of materials, routings and work centres', 'group' => 'Production'],
        'production.plan' => ['label' => 'Create, release and cancel production orders', 'group' => 'Production'],
        'production.issue' => ['label' => 'Issue materials to production orders', 'group' => 'Production'],
        'production.receive' => ['label' => 'Record finished goods output', 'group' => 'Production'],
        'production.qc' => ['label' => 'Run quality checks and release or reject batches', 'group' => 'Production'],
        'production.close' => ['label' => 'Close production orders and post the cost variance', 'group' => 'Production'],
    ],
    'defaults' => [
        User::ROLE_PRODUCTION_MANAGER => [
            'production.view', 'production.manage', 'production.plan', 'production.issue',
            'production.receive', 'production.qc', 'production.close',
        ],
        User::ROLE_WAREHOUSE_MANAGER => ['production.view', 'production.issue', 'production.receive'],
        User::ROLE_STOREKEEPER => ['production.view', 'production.issue', 'production.receive'],
        User::ROLE_ACCOUNTANT => ['production.view', 'production.close'],
        User::ROLE_FINANCE => ['production.view', 'production.close'],
        User::ROLE_CEO => $view,
        User::ROLE_DIRECTOR => $view,
        User::ROLE_AUDITOR => $view,
    ],
    'accounts' => [
        ['1450', 'Work in progress', 'asset', 'wip'],
        ['5410', 'Production labour applied', 'expense', 'labour_applied'],
        ['5420', 'Production overheads applied', 'expense', 'overheads_applied'],
        ['5450', 'Production variance', 'expense', 'production_variance'],
    ],
];
