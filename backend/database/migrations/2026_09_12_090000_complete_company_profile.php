<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The rest of a company's identity.
 *
 * Only the genuinely missing fields are added. Several of the ones asked for
 * already exist under names the codebase uses throughout, and duplicating them
 * would leave two columns that disagree:
 *
 *   physical_address  → `address`            (already on every document)
 *   logo              → `logo_path`
 *   logo_mark         → `logo_mark_path`
 *   is_active         → `status`             (a five-state lifecycle, not a flag:
 *                                             trial / active / past_due /
 *                                             suspended / cancelled)
 *
 * Everything here is nullable. Existing tenants keep working with the details
 * they already have, and a new tenant fills in what it can.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('companies', function (Blueprint $table) {
            // Identity
            $table->string('trading_name', 180)->nullable()->after('legal_name');

            // Reaching them
            $table->string('alternative_phone', 40)->nullable()->after('phone');
            $table->string('postal_address')->nullable()->after('address');
            $table->string('city', 120)->nullable()->after('postal_address');
            $table->string('region', 120)->nullable()->after('city');

            // Registration
            $table->string('business_license_number', 80)->nullable()->after('registration_number');

            // A named human, which is not the same as the billing address.
            $table->string('contact_person', 180)->nullable()->after('business_license_number');
            $table->string('contact_email', 180)->nullable()->after('contact_person');
            $table->string('contact_phone', 40)->nullable()->after('contact_email');

            // Brand: primary and accent already exist; secondary joins them.
            $table->string('secondary_color', 9)->nullable()->after('primary_color');

            // International transfers need it; local ones do not.
            $table->string('swift_code', 24)->nullable()->after('bank_branch');

            // Company lists are searched by name and filtered by status.
            $table->index(['status', 'name'], 'companies_status_name_index');
        });
    }

    public function down(): void
    {
        Schema::table('companies', function (Blueprint $table) {
            $table->dropIndex('companies_status_name_index');
            $table->dropColumn([
                'trading_name', 'alternative_phone', 'postal_address', 'city', 'region',
                'business_license_number', 'contact_person', 'contact_email', 'contact_phone',
                'secondary_color', 'swift_code',
            ]);
        });
    }
};
