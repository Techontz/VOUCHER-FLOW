<?php

use App\Models\User;

/*
 * Sales (quotations, orders, invoices, receipts, returns, price lists) and
 * finance verification & dispatch (loading orders, delivery notes, gate
 * passes, proof of delivery).
 *
 * Separation of duties: a salesperson prepares orders, finance approves them
 * against the credit policy, a cashier records a payment and someone else in
 * finance verifies it, the warehouse loads and the gate lets the truck out.
 */

$view = ['sales.view', 'dispatch.view'];

return [
    'module' => ['sales', 'dispatch'],

    'permissions' => [
        'sales.view' => ['label' => 'View quotations, orders, invoices, receipts and sales reports', 'group' => 'Sales'],
        'sales.quote' => ['label' => 'Prepare quotations', 'group' => 'Sales'],
        'sales.order' => ['label' => 'Prepare and submit sales orders', 'group' => 'Sales'],
        'sales.approve' => ['label' => 'Approve sales orders and override the credit policy with a reason', 'group' => 'Sales'],
        'sales.invoice' => ['label' => 'Raise and post sales invoices', 'group' => 'Sales'],
        'sales.receipt' => ['label' => 'Record customer receipts', 'group' => 'Sales'],
        'sales.return' => ['label' => 'Raise and post credit notes and returns', 'group' => 'Sales'],
        'sales.pricing' => ['label' => 'Maintain price lists and customer pricing', 'group' => 'Sales'],

        'dispatch.view' => ['label' => 'View loading orders, delivery notes and gate passes', 'group' => 'Dispatch'],
        'dispatch.verify' => ['label' => 'Verify customer payments (finance verification)', 'group' => 'Dispatch'],
        'dispatch.load' => ['label' => 'Create loading orders, enter loaded quantities and confirm loading', 'group' => 'Dispatch'],
        'dispatch.deliver' => ['label' => 'Record proof of delivery', 'group' => 'Dispatch'],
        'dispatch.gatepass' => ['label' => 'Confirm at the gate and issue gate passes', 'group' => 'Dispatch'],
        'dispatch.resolve' => ['label' => 'Decide short deliveries: return to stock or write off', 'group' => 'Dispatch'],
    ],

    'defaults' => [
        User::ROLE_SALES => [...$view, 'sales.quote', 'sales.order'],
        User::ROLE_FINANCE => [
            ...$view, 'sales.approve', 'sales.invoice', 'sales.receipt', 'sales.return', 'sales.pricing',
            'dispatch.verify', 'dispatch.resolve',
        ],
        User::ROLE_ACCOUNTANT => [...$view, 'sales.invoice', 'sales.receipt', 'dispatch.verify'],
        User::ROLE_CASHIER => [...$view, 'sales.receipt'],
        User::ROLE_DISPATCH => [...$view, 'dispatch.load', 'dispatch.deliver', 'dispatch.gatepass'],
        User::ROLE_WAREHOUSE_MANAGER => [...$view, 'dispatch.load', 'dispatch.deliver', 'dispatch.gatepass', 'dispatch.resolve'],
        User::ROLE_STOREKEEPER => ['dispatch.view', 'dispatch.load'],
        User::ROLE_CEO => $view,
        User::ROLE_DIRECTOR => $view,
        User::ROLE_AUDITOR => $view,
        User::ROLE_MANAGER => $view,
    ],

    'accounts' => [
        ['4010', 'Sales returns and allowances', 'income', 'sales_returns'],
        ['5010', 'Goods lost in transit', 'expense', 'transit_losses'],
    ],
];
