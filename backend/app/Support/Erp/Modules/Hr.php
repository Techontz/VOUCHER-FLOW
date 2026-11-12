<?php

use App\Models\User;

/*
 * HR Flow & payroll: people, attendance, leave, payroll and the statutory
 * deductions that go with it.
 *
 * Salary and disciplinary data sit behind their own permissions (hr.salary,
 * hr.discipline), separate from hr.view, so a manager can read the staff list
 * without reading anybody's pay. Preparing, authorising and posting a payroll
 * are three permissions, and the authoriser can never be the preparer.
 */

$all = [
    'hr.view', 'hr.manage', 'hr.salary', 'hr.attendance', 'hr.leave.approve', 'hr.recruit',
    'hr.payroll.prepare', 'hr.payroll.post', 'hr.discipline', 'hr.self',
];

$self = ['hr.self'];

return [
    'module' => 'hr',

    'permissions' => [
        'hr.view' => ['label' => 'View employees, attendance, leave and HR records', 'group' => 'HR & payroll'],
        'hr.manage' => ['label' => 'Manage employee records, contracts, transfers and exits', 'group' => 'HR & payroll'],
        'hr.salary' => ['label' => 'See and edit salaries, allowances and bank details', 'group' => 'HR & payroll'],
        'hr.attendance' => ['label' => 'Record and import attendance, manage shifts', 'group' => 'HR & payroll'],
        'hr.leave.approve' => ['label' => 'Approve leave requests (own department unless HR)', 'group' => 'HR & payroll'],
        'hr.recruit' => ['label' => 'Manage vacancies, applicants and onboarding', 'group' => 'HR & payroll'],
        'hr.payroll.prepare' => ['label' => 'Prepare payroll runs, loans and pay items', 'group' => 'HR & payroll'],
        'hr.payroll.authorise' => ['label' => 'Authorise and lock payroll runs (not ones you prepared)', 'group' => 'HR & payroll'],
        'hr.payroll.post' => ['label' => 'Post payroll to the ledger and record salary payment', 'group' => 'HR & payroll'],
        'hr.discipline' => ['label' => 'View and manage disciplinary cases', 'group' => 'HR & payroll'],
        'hr.self' => ['label' => 'My HR: own profile, payslips, leave and attendance', 'group' => 'HR & payroll'],
    ],

    'defaults' => [
        User::ROLE_HR_MANAGER => $all,
        User::ROLE_FINANCE => ['hr.view', 'hr.salary', 'hr.payroll.authorise', 'hr.payroll.post', ...$self],
        User::ROLE_ACCOUNTANT => ['hr.payroll.post', ...$self],
        User::ROLE_CEO => ['hr.view', 'hr.payroll.authorise', ...$self],
        User::ROLE_DIRECTOR => ['hr.view', ...$self],
        User::ROLE_HOD => ['hr.leave.approve', ...$self],
        User::ROLE_MANAGER => ['hr.leave.approve', ...$self],
        User::ROLE_AUDITOR => $self,
        User::ROLE_CASHIER => $self,
        User::ROLE_PROCUREMENT => $self,
        User::ROLE_WAREHOUSE_MANAGER => $self,
        User::ROLE_STOREKEEPER => $self,
        User::ROLE_PRODUCTION_MANAGER => $self,
        User::ROLE_DISPATCH => $self,
        User::ROLE_SALES => $self,
        User::ROLE_FLEET_MANAGER => $self,
        User::ROLE_DRIVER => $self,
        User::ROLE_EMPLOYEE => $self,
    ],

    'accounts' => [
        ['2310', 'PAYE payable', 'liability', 'paye_payable'],
        ['2320', 'NSSF payable', 'liability', 'nssf_payable'],
        ['2330', 'WCF payable', 'liability', 'wcf_payable'],
        ['2340', 'SDL payable', 'liability', 'sdl_payable'],
        ['2350', 'HESLB payable', 'liability', 'heslb_payable'],
        ['2360', 'Net salaries payable', 'liability', 'net_salaries_payable'],
        ['2370', 'Staff loan recoveries', 'liability', 'staff_loan_recoveries'],
        ['2380', 'Other payroll deductions payable', 'liability', 'payroll_deductions_payable'],
        ['6010', 'NSSF employer contribution', 'expense', 'nssf_employer_expense'],
        ['6020', 'WCF contribution', 'expense', 'wcf_expense'],
        ['6030', 'Skills development levy', 'expense', 'sdl_expense'],
    ],
];
