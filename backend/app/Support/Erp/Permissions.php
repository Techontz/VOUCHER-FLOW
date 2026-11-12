<?php

namespace App\Support\Erp;

use App\Models\Erp\CompanyRole;
use App\Models\User;

/**
 * Every ERP permission, and what each built-in role is granted by default.
 *
 * A permission is "module.action". A tenant may re-scope a built-in role or
 * define one of its own through company_roles; a role with no row there keeps
 * the defaults below. A company administrator always holds every permission,
 * so a tenant can never lock itself out of its own configuration.
 *
 * VouchFlow's approval rights are deliberately NOT here: who may sign, approve
 * or pay a voucher is a property of the workflow step, not of a role.
 */
class Permissions
{
    /** @var array<string, array{label: string, group: string}> */
    public const CATALOGUE = [
        'erp.configure' => ['label' => 'Configure the business and its modules', 'group' => 'Administration'],
        'roles.manage' => ['label' => 'Create roles and assign permissions', 'group' => 'Administration'],

        'inventory.view' => ['label' => 'View products, stock and movements', 'group' => 'Inventory'],
        'inventory.manage' => ['label' => 'Manage products, units, categories and warehouses', 'group' => 'Inventory'],
        'inventory.receive' => ['label' => 'Prepare goods received and opening stock', 'group' => 'Inventory'],
        'inventory.issue' => ['label' => 'Prepare stock issues', 'group' => 'Inventory'],
        'inventory.transfer' => ['label' => 'Prepare transfers between locations', 'group' => 'Inventory'],
        'inventory.adjust' => ['label' => 'Prepare adjustments and stock counts', 'group' => 'Inventory'],
        'inventory.post' => ['label' => 'Post stock documents to the ledger', 'group' => 'Inventory'],
        'inventory.reverse' => ['label' => 'Reverse posted stock documents', 'group' => 'Inventory'],

        'customers.view' => ['label' => 'View customers', 'group' => 'Sales'],
        'customers.manage' => ['label' => 'Create and edit customers, credit limits and terms', 'group' => 'Sales'],

        'suppliers.view' => ['label' => 'View suppliers', 'group' => 'Procurement'],
        'suppliers.manage' => ['label' => 'Create and edit suppliers and their bank details', 'group' => 'Procurement'],

        'accounting.view' => ['label' => 'View the chart of accounts, journals and trial balance', 'group' => 'Finance'],
        'accounting.manage' => ['label' => 'Maintain the chart of accounts', 'group' => 'Finance'],
        'accounting.post' => ['label' => 'Post manual journal entries', 'group' => 'Finance'],
        'accounting.reverse' => ['label' => 'Reverse posted journal entries', 'group' => 'Finance'],
    ];

    private const VIEW_ALL = ['inventory.view', 'customers.view', 'suppliers.view', 'accounting.view'];

    /**
     * Defaults per built-in role. Separation of duties is intentional: a
     * storekeeper prepares documents, a warehouse manager posts them; an
     * accountant posts journals, only finance may reverse them.
     *
     * @var array<string, list<string>>
     */
    public const DEFAULTS = [
        User::ROLE_CEO => self::VIEW_ALL,
        User::ROLE_DIRECTOR => self::VIEW_ALL,
        User::ROLE_AUDITOR => self::VIEW_ALL,
        User::ROLE_FINANCE => [
            ...self::VIEW_ALL, 'customers.manage', 'suppliers.manage',
            'accounting.manage', 'accounting.post', 'accounting.reverse',
        ],
        User::ROLE_ACCOUNTANT => [...self::VIEW_ALL, 'accounting.post'],
        User::ROLE_CASHIER => ['customers.view', 'suppliers.view'],
        User::ROLE_PROCUREMENT => ['inventory.view', 'inventory.receive', 'suppliers.view', 'suppliers.manage'],
        User::ROLE_WAREHOUSE_MANAGER => [
            'inventory.view', 'inventory.manage', 'inventory.receive', 'inventory.issue',
            'inventory.transfer', 'inventory.adjust', 'inventory.post', 'inventory.reverse', 'suppliers.view',
        ],
        User::ROLE_STOREKEEPER => [
            'inventory.view', 'inventory.receive', 'inventory.issue', 'inventory.transfer', 'inventory.adjust',
        ],
        User::ROLE_PRODUCTION_MANAGER => ['inventory.view', 'inventory.issue'],
        User::ROLE_DISPATCH => ['inventory.view', 'customers.view'],
        User::ROLE_SALES => ['inventory.view', 'customers.view', 'customers.manage'],
        User::ROLE_HOD => ['inventory.view'],
        User::ROLE_MANAGER => ['inventory.view', 'customers.view', 'suppliers.view'],
        User::ROLE_FLEET_MANAGER => ['inventory.view', 'suppliers.view'],
        User::ROLE_HR_MANAGER => [],
        User::ROLE_DRIVER => [],
        User::ROLE_EMPLOYEE => [],
    ];

    /** @var array<string, list<string>> per-request memo, keyed by user and role */
    private array $resolved = [];

    /** @return list<string> */
    public function for(User $user): array
    {
        return $this->resolved["{$user->id}:{$user->role}"] ??= $this->resolve($user);
    }

    public function allows(User $user, string $permission): bool
    {
        return in_array($permission, $this->for($user), true);
    }

    public function forget(): void
    {
        $this->resolved = [];
    }

    /** @return list<string> */
    public static function all(): array
    {
        return array_keys(self::catalogue());
    }

    /**
     * The core catalogue and every module's permissions.
     *
     * @return array<string, array{label: string, group: string}>
     */
    public static function catalogue(): array
    {
        return [...self::CATALOGUE, ...ModuleRegistry::permissions()];
    }

    /** @return list<string> */
    public static function defaultsFor(string $role): array
    {
        if ($role === User::ROLE_COMPANY_ADMIN) {
            return self::all();
        }

        return array_values(array_unique([...(self::DEFAULTS[$role] ?? []), ...ModuleRegistry::defaultsFor($role)]));
    }

    /** @return list<string> */
    private function resolve(User $user): array
    {
        if ($user->isCompanyAdmin()) {
            return self::all();
        }

        // A super admin inspecting a tenant reads it; changing it is the
        // tenant's own business.
        if ($user->isSuperAdmin()) {
            return array_values(array_filter(self::all(), fn ($p) => str_ends_with($p, '.view')));
        }

        $custom = CompanyRole::query()->where('key', $user->role)->first();

        $granted = $custom ? $custom->permissions : self::defaultsFor($user->role);

        // Anything a stored role names that the platform no longer defines is dropped.
        return array_values(array_intersect(self::all(), $granted));
    }
}
