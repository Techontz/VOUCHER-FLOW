<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The rest of a company's identity.
 *
 * Only the genuinely missing fields are added. Several of the ones a complete
 * company profile calls for already exist under the names the codebase uses
 * throughout, and duplicating them would leave two columns free to disagree:
 *
 *   physical_address  → `address`            (already on every document)
 *   logo              → `logo_path`
 *   logo_mark         → `logo_mark_path`
 *   is_active         → `status`             (a five-state lifecycle, not a
 *                                             flag: trial / active / past_due /
 *                                             suspended / cancelled)
 *
 * Every column is nullable, so existing tenants keep working with the details
 * they already have and a new tenant fills in what it can.
 *
 * WRITTEN TO BE SAFE TO RUN ON A SCHEMA THAT IS PARTLY THERE.
 * Each column is added only if it is absent, and the index only if it is not
 * already defined. A server where some of this was applied by hand — or where
 * this migration was interrupted — can run it without hitting
 * "Duplicate column name". Nothing here drops or rewrites existing data.
 */
return new class extends Migration
{
    /**
     * column => the column it should sit after.
     *
     * Every anchor either already exists (from create_companies_table or
     * extend_company_branding) or is added earlier in this same statement,
     * which MySQL resolves within one ALTER TABLE.
     */
    private const COLUMNS = [
        // Identity
        'trading_name' => 'legal_name',

        // Reaching them
        'alternative_phone' => 'phone',
        'postal_address' => 'address',
        'city' => 'postal_address',
        'region' => 'city',

        // Registration
        'business_license_number' => 'registration_number',

        // A named human, which is not the same as the billing address.
        'contact_person' => 'business_license_number',
        'contact_email' => 'contact_person',
        'contact_phone' => 'contact_email',

        // Brand: primary and accent already exist; secondary joins them.
        'secondary_color' => 'primary_color',

        // International transfers need it; local ones do not.
        'swift_code' => 'bank_branch',
    ];

    private const INDEX = 'companies_status_name_index';

    public function up(): void
    {
        $missing = array_filter(
            self::COLUMNS,
            fn ($after, $column) => ! Schema::hasColumn('companies', $column),
            ARRAY_FILTER_USE_BOTH,
        );

        if ($missing !== []) {
            Schema::table('companies', function (Blueprint $table) use ($missing) {
                foreach ($missing as $column => $after) {
                    $definition = match ($column) {
                        'trading_name', 'contact_person' => $table->string($column, 180),
                        'alternative_phone', 'contact_phone' => $table->string($column, 40),
                        'contact_email' => $table->string($column, 180),
                        'postal_address' => $table->string($column),
                        'city', 'region' => $table->string($column, 120),
                        'business_license_number' => $table->string($column, 80),
                        'secondary_color' => $table->string($column, 9),
                        'swift_code' => $table->string($column, 24),
                    };

                    $definition->nullable();

                    // Only anchor to a column that will be there. If the anchor
                    // is itself missing and not part of this batch, appending is
                    // correct — position is cosmetic, presence is not.
                    if (Schema::hasColumn('companies', $after) || isset($missing[$after])) {
                        $definition->after($after);
                    }
                }
            });
        }

        // Company lists are searched by name and filtered by status.
        if (! $this->hasIndex(self::INDEX)) {
            Schema::table('companies', function (Blueprint $table) {
                $table->index(['status', 'name'], self::INDEX);
            });
        }
    }

    public function down(): void
    {
        if ($this->hasIndex(self::INDEX)) {
            Schema::table('companies', function (Blueprint $table) {
                $table->dropIndex(self::INDEX);
            });
        }

        $present = array_values(array_filter(
            array_keys(self::COLUMNS),
            fn ($column) => Schema::hasColumn('companies', $column),
        ));

        if ($present !== []) {
            Schema::table('companies', function (Blueprint $table) use ($present) {
                $table->dropColumn($present);
            });
        }
    }

    /**
     * Schema::hasIndex exists in newer Laravel but is not universally available
     * across the versions this project has run on, so ask the connection.
     */
    private function hasIndex(string $name): bool
    {
        $database = DB::connection()->getDatabaseName();

        return DB::table('information_schema.statistics')
            ->where('table_schema', $database)
            ->where('table_name', 'companies')
            ->where('index_name', $name)
            ->exists();
    }
};
