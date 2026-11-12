<?php

use App\Models\User;

/*
 * CRM and document management.
 *
 * A salesperson works their own leads and opportunities; crm.view_all lets a
 * manager see everyone's, and crm.assign hand records between people.
 * Everyone may open documents, but only those their folder and the document
 * itself share with them; documents.manage sees and administers them all.
 */

$upload = ['documents.view', 'documents.upload'];

return [
    'module' => ['crm', 'documents'],

    'permissions' => [
        'crm.view' => ['label' => 'View leads, opportunities and activities (their own)', 'group' => 'CRM'],
        'crm.view_all' => ['label' => 'See every salesperson\'s CRM records', 'group' => 'CRM'],
        'crm.manage' => ['label' => 'Create and update leads, opportunities and activities', 'group' => 'CRM'],
        'crm.assign' => ['label' => 'Assign CRM records to another person', 'group' => 'CRM'],

        'documents.view' => ['label' => 'Open documents shared with them', 'group' => 'Documents'],
        'documents.upload' => ['label' => 'Upload documents and new versions', 'group' => 'Documents'],
        'documents.manage' => ['label' => 'Manage folders, access, retention and restore', 'group' => 'Documents'],
        'documents.delete' => ['label' => 'Delete documents once retention allows', 'group' => 'Documents'],
    ],

    'defaults' => [
        User::ROLE_SALES => ['crm.view', 'crm.manage', ...$upload],
        User::ROLE_MANAGER => ['crm.view', 'crm.view_all', 'crm.assign', ...$upload],
        User::ROLE_CEO => ['crm.view', 'crm.view_all', 'crm.assign', ...$upload, 'documents.manage', 'documents.delete'],
        User::ROLE_DIRECTOR => ['crm.view', 'crm.view_all', 'crm.assign', ...$upload],
        User::ROLE_HOD => $upload,
        User::ROLE_FINANCE => $upload,
        User::ROLE_ACCOUNTANT => $upload,
        User::ROLE_HR_MANAGER => $upload,
        User::ROLE_FLEET_MANAGER => $upload,
        User::ROLE_PROCUREMENT => $upload,
        User::ROLE_WAREHOUSE_MANAGER => $upload,
        User::ROLE_AUDITOR => ['documents.view'],
        User::ROLE_CASHIER => ['documents.view'],
        User::ROLE_STOREKEEPER => ['documents.view'],
        User::ROLE_PRODUCTION_MANAGER => ['documents.view'],
        User::ROLE_DISPATCH => ['documents.view'],
        User::ROLE_DRIVER => ['documents.view'],
        User::ROLE_EMPLOYEE => ['documents.view'],
    ],

    'accounts' => [],
];
