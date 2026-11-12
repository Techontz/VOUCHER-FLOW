<?php

namespace App\Support\Erp;

/**
 * The ERP modules added after the core, each described by one file in
 * app/Support/Erp/Modules. A module file returns an array:
 *
 *   'module'      => 'fleet',                      // the BusinessTemplates key it makes live
 *   'permissions' => ['fleet.view' => ['label' => ..., 'group' => ...]],
 *   'defaults'    => [User::ROLE_FLEET_MANAGER => ['fleet.view', ...]],
 *   'accounts'    => [['6150', 'Fuel', 'expense', 'fuel'], ...],   // added to the chart
 *
 * Routes live beside it in routes/erp/{name}.php and demo data in
 * database/seeders/Erp. Adding a module therefore never edits a file another
 * module owns.
 */
class ModuleRegistry
{
    /** @var list<array<string, mixed>>|null */
    private static ?array $loaded = null;

    /** @return list<array<string, mixed>> */
    public static function all(): array
    {
        if (self::$loaded !== null) {
            return self::$loaded;
        }

        $files = glob(__DIR__.'/Modules/*.php') ?: [];
        sort($files);

        return self::$loaded = array_values(array_map(fn (string $file) => require $file, $files));
    }

    /** @return array<string, array{label: string, group: string}> */
    public static function permissions(): array
    {
        return array_merge(...array_map(fn ($m) => $m['permissions'] ?? [], self::all()), ...[[]]);
    }

    /** @return list<string> */
    public static function defaultsFor(string $role): array
    {
        $granted = [];
        foreach (self::all() as $module) {
            array_push($granted, ...($module['defaults'][$role] ?? []));
        }

        return array_values(array_unique($granted));
    }

    /** @return list<string> module keys made live by a module file */
    public static function liveModules(): array
    {
        return array_values(array_unique(array_merge(...array_map(fn ($m) => (array) ($m['module'] ?? []), self::all()), ...[[]])));
    }

    /** @return list<array{0: string, 1: string, 2: string, 3: string}> */
    public static function accounts(): array
    {
        return array_merge(...array_map(fn ($m) => $m['accounts'] ?? [], self::all()), ...[[]]);
    }
}
