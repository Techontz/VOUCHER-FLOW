<?php

use App\Models\User;

/*
 * Fleet & transport: vehicles (owned and hired), drivers, trips with the four
 * transport cost options, fuel against consumption standards, trip expenses,
 * maintenance, tyres, downtime and trip profitability.
 *
 * Drivers hold fleet.own rather than fleet.view: they see their own trips and
 * nothing else, and what they record waits for someone with fleet.approve.
 */

$all = [
    'fleet.view', 'fleet.manage', 'fleet.trips', 'fleet.fuel',
    'fleet.expenses', 'fleet.maintenance', 'fleet.approve',
];

return [
    'module' => 'fleet',

    'permissions' => [
        'fleet.view' => ['label' => 'View vehicles, every trip, fuel, maintenance and fleet reports', 'group' => 'Fleet'],
        'fleet.own' => ['label' => 'See own trips and record their fuel and expenses (drivers)', 'group' => 'Fleet'],
        'fleet.manage' => ['label' => 'Manage vehicles, drivers and fuel standards', 'group' => 'Fleet'],
        'fleet.trips' => ['label' => 'Plan, dispatch, complete and close trips', 'group' => 'Fleet'],
        'fleet.fuel' => ['label' => 'Issue fuel on trips', 'group' => 'Fleet'],
        'fleet.expenses' => ['label' => 'Record trip expenses and driver allowances', 'group' => 'Fleet'],
        'fleet.maintenance' => ['label' => 'Record maintenance, tyres and downtime', 'group' => 'Fleet'],
        'fleet.approve' => ['label' => 'Approve fuel and expenses, and close trips over the fuel standard', 'group' => 'Fleet'],
    ],

    'defaults' => [
        User::ROLE_FLEET_MANAGER => $all,
        User::ROLE_DISPATCH => ['fleet.view', 'fleet.trips'],
        User::ROLE_DRIVER => ['fleet.own'],
        User::ROLE_FINANCE => ['fleet.view', 'fleet.approve'],
        User::ROLE_ACCOUNTANT => ['fleet.view', 'fleet.approve'],
        User::ROLE_CEO => ['fleet.view'],
        User::ROLE_DIRECTOR => ['fleet.view'],
        User::ROLE_AUDITOR => ['fleet.view'],
    ],

    'accounts' => [
        ['6110', 'Driver allowances', 'expense', 'fleet_allowances'],
        ['6120', 'Road tolls & parking', 'expense', 'fleet_tolls'],
        ['6130', 'Loading & offloading fees', 'expense', 'fleet_loading'],
        ['6140', 'Other trip expenses', 'expense', 'fleet_trip_other'],
        ['6210', 'Vehicle hire', 'expense', 'fleet_vehicle_hire'],
    ],
];
