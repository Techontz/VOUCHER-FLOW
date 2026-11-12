<?php

use App\Models\User;

/*
 * Finance & assets: banking, the general cashbook, bank reconciliation,
 * financial statements, period closing, budgets and fixed assets.
 *
 * Finance extends the core 'accounting' module; fixed assets are the
 * 'assets' module. Bank and mobile money ledger accounts (1201-1299) are
 * created per bank account as it is registered, so they are not listed here.
 */

$finance = ['finance.view', 'finance.bank', 'finance.cashbook', 'finance.statements', 'finance.close', 'finance.budget'];
$assets = ['assets.view', 'assets.manage', 'assets.depreciate', 'assets.dispose'];
$readers = ['finance.view', 'finance.statements', 'assets.view'];

return [
    'module' => ['assets'],

    'permissions' => [
        'finance.view' => ['label' => 'View bank accounts, the cashbook, periods and budgets', 'group' => 'Finance'],
        'finance.bank' => ['label' => 'Manage bank accounts, transfers and reconciliations', 'group' => 'Finance'],
        'finance.cashbook' => ['label' => 'Record general receipts and payments', 'group' => 'Finance'],
        'finance.statements' => ['label' => 'View financial statements and budget against actual', 'group' => 'Finance'],
        'finance.close' => ['label' => 'Close and reopen accounting periods and the year', 'group' => 'Finance'],
        'finance.budget' => ['label' => 'Prepare and edit budgets', 'group' => 'Finance'],
        'assets.view' => ['label' => 'View the fixed asset register', 'group' => 'Fixed assets'],
        'assets.manage' => ['label' => 'Register, capitalise and transfer assets; maintain asset classes', 'group' => 'Fixed assets'],
        'assets.depreciate' => ['label' => 'Run and post monthly depreciation', 'group' => 'Fixed assets'],
        'assets.dispose' => ['label' => 'Dispose of assets', 'group' => 'Fixed assets'],
    ],

    'defaults' => [
        User::ROLE_FINANCE => [...$finance, ...$assets],
        User::ROLE_ACCOUNTANT => ['finance.view', 'finance.bank', 'finance.cashbook', 'finance.statements', 'assets.view', 'assets.depreciate'],
        User::ROLE_CEO => $readers,
        User::ROLE_DIRECTOR => $readers,
        User::ROLE_AUDITOR => $readers,
    ],

    'accounts' => [
        ['1520', 'Plant & machinery', 'asset', 'fa_plant'],
        ['1525', 'Accumulated depreciation: plant & machinery', 'asset', 'fa_plant_depreciation'],
        ['1530', 'Motor vehicles', 'asset', 'fa_vehicles'],
        ['1535', 'Accumulated depreciation: motor vehicles', 'asset', 'fa_vehicles_depreciation'],
        ['1540', 'Computers & IT equipment', 'asset', 'fa_computers'],
        ['1545', 'Accumulated depreciation: computers', 'asset', 'fa_computers_depreciation'],
        ['1550', 'Furniture & fittings', 'asset', 'fa_furniture'],
        ['1555', 'Accumulated depreciation: furniture', 'asset', 'fa_furniture_depreciation'],
        ['1560', 'Buildings', 'asset', 'fa_buildings'],
        ['1565', 'Accumulated depreciation: buildings', 'asset', 'fa_buildings_depreciation'],
        ['3200', 'Owner capital contributions', 'equity', 'owner_capital'],
        ['3250', 'Drawings', 'equity', 'drawings'],
        ['6600', 'Depreciation', 'expense', 'depreciation'],
        ['6610', 'Bank charges', 'expense', 'bank_charges'],
        ['6620', 'Loss on disposal of assets', 'expense', 'disposal_loss'],
        ['6630', 'Insurance', 'expense', 'general_insurance'],
        ['6640', 'Professional fees', 'expense', 'professional_fees'],
        ['6650', 'Communication & internet', 'expense', 'communication_costs'],
    ],
];
