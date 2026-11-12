<?php

use App\Models\User;

/*
 * Procurement: requisitions, requests for quotation, purchase orders,
 * receiving against them, supplier invoices matched three ways, and supplier
 * payments. Suppliers themselves are core.
 *
 * Separation of duties: the person who raises a requisition is not the one
 * who approves it, the officer who orders is not the one who posts the
 * supplier's invoice, and paying is a permission of its own.
 */
return [
    'module' => 'procurement',

    'permissions' => [
        'procurement.view' => ['label' => 'View requisitions, orders, supplier invoices and payables', 'group' => 'Procurement'],
        'procurement.request' => ['label' => 'Raise purchase requisitions', 'group' => 'Procurement'],
        'procurement.approve' => ['label' => 'Approve requisitions, purchase orders and invoice variances', 'group' => 'Procurement'],
        'procurement.quote' => ['label' => 'Send requests for quotation and record supplier quotations', 'group' => 'Procurement'],
        'procurement.order' => ['label' => 'Raise, send and close purchase orders', 'group' => 'Procurement'],
        'procurement.receive' => ['label' => 'Receive goods and confirm services against purchase orders', 'group' => 'Procurement'],
        'procurement.invoice' => ['label' => 'Record, match and post supplier invoices', 'group' => 'Procurement'],
        'procurement.pay' => ['label' => 'Record and post supplier payments', 'group' => 'Procurement'],
    ],

    'defaults' => [
        User::ROLE_PROCUREMENT => ['procurement.view', 'procurement.request', 'procurement.quote', 'procurement.order', 'procurement.receive'],
        User::ROLE_HOD => ['procurement.view', 'procurement.request', 'procurement.approve'],
        User::ROLE_MANAGER => ['procurement.view', 'procurement.request', 'procurement.approve'],
        User::ROLE_FINANCE => ['procurement.view', 'procurement.approve', 'procurement.invoice', 'procurement.pay'],
        User::ROLE_ACCOUNTANT => ['procurement.view', 'procurement.invoice'],
        User::ROLE_CASHIER => ['procurement.view', 'procurement.pay'],
        User::ROLE_STOREKEEPER => ['procurement.view', 'procurement.receive'],
        User::ROLE_WAREHOUSE_MANAGER => ['procurement.view', 'procurement.receive'],
        User::ROLE_CEO => ['procurement.view', 'procurement.approve'],
        User::ROLE_DIRECTOR => ['procurement.view'],
        User::ROLE_AUDITOR => ['procurement.view'],
    ],

    'accounts' => [
        ['5110', 'Purchase price variance', 'expense', 'purchase_price_variance'],
        ['5120', 'Purchase quantity variance', 'expense', 'purchase_quantity_variance'],
    ],
];
