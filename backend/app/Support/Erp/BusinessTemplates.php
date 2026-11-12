<?php

namespace App\Support\Erp;

/**
 * The starting points a company chooses from in the setup wizard.
 *
 * A template only pre-fills: the modules it recommends, the units and
 * categories it seeds, the extra product fields its trade needs and the
 * tracking a product starts with. Everything it sets stays editable in
 * settings afterwards, the template is never consulted again once applied.
 */
class BusinessTemplates
{
    /**
     * Modules the platform knows about. `live` says whether this release
     * ships the module; a company may still plan for one that is coming.
     *
     * @var array<string, array{label: string, phase: int, live: bool}>
     */
    public const MODULES = [
        'vouchflow' => ['label' => 'VouchFlow payment vouchers', 'phase' => 0, 'live' => true],
        'inventory' => ['label' => 'Inventory & warehouses', 'phase' => 1, 'live' => true],
        'sales' => ['label' => 'Sales & customers', 'phase' => 1, 'live' => true],
        'procurement' => ['label' => 'Procurement & suppliers', 'phase' => 1, 'live' => true],
        'accounting' => ['label' => 'Finance & accounting', 'phase' => 1, 'live' => true],
        'production' => ['label' => 'Production & manufacturing', 'phase' => 2, 'live' => false],
        'dispatch' => ['label' => 'Dispatch & delivery', 'phase' => 2, 'live' => false],
        'fleet' => ['label' => 'Fleet & transport', 'phase' => 3, 'live' => false],
        'hr' => ['label' => 'HR Flow & payroll', 'phase' => 4, 'live' => false],
        'crm' => ['label' => 'CRM', 'phase' => 6, 'live' => false],
        'assets' => ['label' => 'Asset management', 'phase' => 6, 'live' => false],
        'documents' => ['label' => 'Document management', 'phase' => 6, 'live' => false],
    ];

    /**
     * MODULES with each module's live flag settled: a module is live when
     * this release ships it, either in the core or through a module file.
     *
     * @return array<string, array{label: string, phase: int, live: bool}>
     */
    public static function modules(): array
    {
        $live = ModuleRegistry::liveModules();

        $modules = [];
        foreach (self::MODULES as $key => $module) {
            $modules[$key] = [...$module, 'live' => $module['live'] || in_array($key, $live, true)];
        }

        return $modules;
    }

    private const CORE = ['vouchflow', 'inventory', 'sales', 'procurement', 'accounting'];

    private const PIECE = ['code' => 'PCS', 'name' => 'Piece', 'allows_decimals' => false];

    private const CARTON = ['code' => 'CTN', 'name' => 'Carton', 'allows_decimals' => false];

    private const BOX = ['code' => 'BOX', 'name' => 'Box', 'allows_decimals' => false];

    private const LITRE = ['code' => 'LTR', 'name' => 'Litre', 'allows_decimals' => true];

    private const KG = ['code' => 'KG', 'name' => 'Kilogram', 'allows_decimals' => true];

    private const METRE = ['code' => 'MTR', 'name' => 'Metre', 'allows_decimals' => true];

    private const SET = ['code' => 'SET', 'name' => 'Set', 'allows_decimals' => false];

    /**
     * @return array<string, array{
     *     label: string, label_sw: string, description: string, icon: string,
     *     modules: list<string>, units: list<array{code: string, name: string, allows_decimals: bool}>,
     *     categories: list<string>,
     *     product_fields: list<array{key: string, label: string, type: string}>,
     *     product_defaults: array<string, bool>,
     *     settings: array<string, mixed>
     * }>
     */
    public static function all(): array
    {
        return [
            'general' => self::make('General business', 'Biashara ya jumla', 'A clean starting point you shape yourself.', 'ph-storefront',
                self::CORE, [self::PIECE, self::BOX, self::KG], ['General']),

            'manufacturing' => self::make('Manufacturing factory', 'Kiwanda cha uzalishaji', 'Raw materials, bills of materials, production orders and finished goods.', 'ph-factory',
                [...self::CORE, 'production', 'dispatch', 'fleet', 'hr'], [self::PIECE, self::CARTON, self::KG, self::LITRE],
                ['Raw materials', 'Packaging materials', 'Finished goods', 'Spare parts'],
                [], ['track_batches' => true]),

            'beverage' => self::make('Beverage factory & depot', 'Kiwanda cha vinywaji na depo', 'Water and soft drinks: production, finance verification, loading orders and delivery.', 'ph-drop',
                [...self::CORE, 'production', 'dispatch', 'fleet', 'hr'], [self::CARTON, self::PIECE, self::LITRE, self::KG, ['code' => 'CRT', 'name' => 'Crate', 'allows_decimals' => false]],
                ['Raw materials', 'Preforms & caps', 'Labels & packaging', 'Bottled water', 'Soft drinks'],
                [['key' => 'pack_size', 'label' => 'Pack size', 'type' => 'text']], ['track_batches' => true, 'track_expiry' => true]),

            'wholesale' => self::make('Wholesale & distribution', 'Jumla na usambazaji', 'Bulk sales, carton and piece units, customer credit limits and price lists.', 'ph-package',
                [...self::CORE, 'dispatch', 'fleet'], [self::CARTON, self::PIECE, self::BOX, self::KG],
                ['Food & groceries', 'Beverages', 'Household', 'Personal care'],
                [['key' => 'pieces_per_carton', 'label' => 'Pieces per carton', 'type' => 'number']]),

            'retail' => self::make('Retail shop', 'Duka la rejareja', 'Over-the-counter sales with barcodes and minimum stock alerts.', 'ph-shopping-bag',
                self::CORE, [self::PIECE, self::BOX, self::KG], ['General merchandise']),

            'supermarket' => self::make('Supermarket / mini-market', 'Supamaketi', 'Many products, barcodes, expiry dates and fast-moving stock.', 'ph-shopping-cart',
                self::CORE, [self::PIECE, self::CARTON, self::KG, self::LITRE],
                ['Fresh produce', 'Dairy', 'Bakery', 'Beverages', 'Household', 'Personal care'],
                [], ['track_expiry' => true]),

            'pharmacy' => self::make('Pharmacy & medical shop', 'Famasia na duka la dawa', 'Batch numbers, expiry dates, stock alerts and full traceability.', 'ph-first-aid-kit',
                self::CORE, [self::PIECE, self::BOX, ['code' => 'STRP', 'name' => 'Strip', 'allows_decimals' => false], ['code' => 'BTL', 'name' => 'Bottle', 'allows_decimals' => false]],
                ['Prescription medicines', 'Over-the-counter', 'Medical supplies', 'Cosmetics'],
                [
                    ['key' => 'generic_name', 'label' => 'Generic name', 'type' => 'text'],
                    ['key' => 'strength', 'label' => 'Strength', 'type' => 'text'],
                    ['key' => 'dosage_form', 'label' => 'Dosage form', 'type' => 'text'],
                    ['key' => 'prescription_only', 'label' => 'Prescription only', 'type' => 'boolean'],
                ],
                ['track_batches' => true, 'track_expiry' => true], ['expiry_alert_days' => 90]),

            'spare_parts' => self::make('Spare parts shop', 'Duka la vipuri', 'Part numbers, brands, compatible vehicle models and alternatives.', 'ph-wrench',
                self::CORE, [self::PIECE, self::SET, ['code' => 'PAIR', 'name' => 'Pair', 'allows_decimals' => false], self::LITRE],
                ['Engine', 'Brakes', 'Suspension', 'Electrical', 'Filters', 'Lubricants'],
                [
                    ['key' => 'part_number', 'label' => 'Part number', 'type' => 'text'],
                    ['key' => 'oem_number', 'label' => 'OEM number', 'type' => 'text'],
                    ['key' => 'compatible_models', 'label' => 'Compatible vehicle models', 'type' => 'text'],
                    ['key' => 'alternative_part', 'label' => 'Alternative part', 'type' => 'text'],
                ]),

            'electronics' => self::make('Electronics & mobile phones', 'Elektroniki na simu', 'Serial and IMEI tracking, brands and warranties.', 'ph-device-mobile',
                self::CORE, [self::PIECE, self::SET, self::BOX], ['Phones', 'Accessories', 'Computers', 'Home electronics'],
                [['key' => 'warranty_months', 'label' => 'Warranty (months)', 'type' => 'number'], ['key' => 'model', 'label' => 'Model', 'type' => 'text']],
                ['track_serials' => true]),

            'clothing' => self::make('Clothing, shoes & household', 'Nguo, viatu na vifaa vya nyumbani', 'Sizes, colours and seasonal stock.', 'ph-t-shirt',
                self::CORE, [self::PIECE, ['code' => 'PAIR', 'name' => 'Pair', 'allows_decimals' => false], self::SET], ['Men', 'Women', 'Children', 'Footwear', 'Household'],
                [['key' => 'size', 'label' => 'Size', 'type' => 'text'], ['key' => 'colour', 'label' => 'Colour', 'type' => 'text']]),

            'hardware' => self::make('Hardware shop', 'Duka la vifaa vya ujenzi', 'Building materials sold by the piece, metre, bag and kilogram.', 'ph-hammer',
                self::CORE, [self::PIECE, self::METRE, self::KG, ['code' => 'BAG', 'name' => 'Bag', 'allows_decimals' => false], self::LITRE],
                ['Cement & aggregates', 'Steel & iron', 'Plumbing', 'Electrical', 'Paint', 'Tools']),

            'hospitality' => self::make('Hotel & restaurant', 'Hoteli na mgahawa', 'Kitchen stores, bar stock, recipes and consumption.', 'ph-fork-knife',
                [...self::CORE, 'hr'], [self::PIECE, self::KG, self::LITRE, ['code' => 'BTL', 'name' => 'Bottle', 'allows_decimals' => false]],
                ['Kitchen stores', 'Bar', 'Housekeeping', 'Maintenance'], [], ['track_expiry' => true]),

            'transport' => self::make('Transport & logistics', 'Usafirishaji na mizigo', 'Vehicles, drivers, trips, fuel, charges and maintenance.', 'ph-truck',
                [...self::CORE, 'fleet', 'hr'], [self::PIECE, self::LITRE, self::SET], ['Fuel & lubricants', 'Tyres', 'Spare parts']),

            'petrol_station' => self::make('Petrol station', 'Kituo cha mafuta', 'Fuel tanks by the litre, shop stock and lubricants.', 'ph-gas-pump',
                self::CORE, [self::LITRE, self::PIECE], ['Fuel', 'Lubricants', 'Shop']),

            'financial_agent' => self::make('Mobile-money & financial agent', 'Wakala wa fedha', 'Float accounts, cash and commissions. Provider integrations are configured separately.', 'ph-money',
                ['vouchflow', 'accounting'], [self::PIECE], ['Services']),
        ];
    }

    public static function get(string $key): ?array
    {
        return self::all()[$key] ?? null;
    }

    /** @return list<string> */
    public static function keys(): array
    {
        return array_keys(self::all());
    }

    private static function make(
        string $label,
        string $labelSw,
        string $description,
        string $icon,
        array $modules,
        array $units,
        array $categories,
        array $productFields = [],
        array $productDefaults = [],
        array $settings = [],
    ): array {
        return [
            'label' => $label,
            'label_sw' => $labelSw,
            'description' => $description,
            'icon' => $icon,
            'modules' => $modules,
            'units' => $units,
            'categories' => $categories,
            'product_fields' => $productFields,
            'product_defaults' => ['track_batches' => false, 'track_expiry' => false, 'track_serials' => false, ...$productDefaults],
            'settings' => $settings,
        ];
    }
}
