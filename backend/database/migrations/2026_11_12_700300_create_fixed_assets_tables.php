<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fixed assets: classes, the register, monthly depreciation and history.
 *
 * Depreciation is written one line per asset per month, and the
 * (asset, period) key refuses a second line for the same month, so an asset
 * can never be depreciated twice for one month however runs are retried.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('asset_classes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('code', 20);
            $table->string('name', 120);
            // straight_line · reducing_balance
            $table->string('method', 20)->default('straight_line');
            $table->unsignedSmallInteger('useful_life_months')->default(60);
            // Annual rate, percent: used by reducing balance.
            $table->decimal('rate', 6, 2)->default(0);
            $table->foreignId('asset_account_id')->constrained('accounts')->restrictOnDelete();
            $table->foreignId('depreciation_account_id')->constrained('accounts')->restrictOnDelete();
            $table->foreignId('expense_account_id')->constrained('accounts')->restrictOnDelete();
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['company_id', 'code']);
        });

        Schema::create('fixed_assets', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('tag', 40);
            $table->string('name', 160);
            $table->string('description', 500)->nullable();
            $table->foreignId('asset_class_id')->constrained()->restrictOnDelete();
            $table->string('serial_number', 80)->nullable();
            $table->string('location', 120)->nullable();
            $table->foreignId('custodian_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('supplier_id')->nullable()->constrained('suppliers')->nullOnDelete();
            $table->date('acquisition_date');
            $table->decimal('cost', 18, 2);
            $table->decimal('residual_value', 18, 2)->default(0);
            $table->string('method', 20);
            $table->unsignedSmallInteger('useful_life_months');
            $table->decimal('rate', 6, 2)->default(0);
            // Kept in step with the posted depreciation lines.
            $table->decimal('accumulated_depreciation', 18, 2)->default(0);
            // draft · active · disposed
            $table->string('status', 20)->default('draft');
            // How the acquisition was paid for: payable · bank
            $table->string('funding', 20)->nullable();
            $table->foreignId('funding_bank_account_id')->nullable()->constrained('bank_accounts')->nullOnDelete();
            $table->foreignId('acquisition_entry_id')->nullable()->constrained('journal_entries')->nullOnDelete();
            $table->timestamp('capitalised_at')->nullable();
            $table->date('disposal_date')->nullable();
            $table->decimal('disposal_proceeds', 18, 2)->nullable();
            $table->decimal('disposal_gain_loss', 18, 2)->nullable();
            $table->foreignId('disposal_bank_account_id')->nullable()->constrained('bank_accounts')->nullOnDelete();
            $table->foreignId('disposal_entry_id')->nullable()->constrained('journal_entries')->nullOnDelete();
            $table->string('disposal_reason', 255)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'tag']);
            $table->index(['company_id', 'status']);
        });

        Schema::create('asset_depreciation_runs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->string('number', 40);
            // YYYY-MM
            $table->string('period', 7);
            $table->date('run_date');
            $table->decimal('total', 18, 2)->default(0);
            $table->unsignedInteger('assets_count')->default(0);
            $table->foreignId('journal_entry_id')->nullable()->constrained('journal_entries')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['company_id', 'period']);
            $table->unique(['company_id', 'number']);
        });

        Schema::create('asset_depreciation_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('asset_depreciation_run_id')->constrained()->cascadeOnDelete();
            $table->foreignId('fixed_asset_id')->constrained()->restrictOnDelete();
            $table->string('period', 7);
            $table->decimal('opening_value', 18, 2);
            $table->decimal('amount', 18, 2);
            $table->decimal('closing_value', 18, 2);
            $table->timestamps();

            $table->unique(['fixed_asset_id', 'period']);
        });

        Schema::create('asset_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('company_id')->constrained()->cascadeOnDelete();
            $table->foreignId('fixed_asset_id')->constrained()->cascadeOnDelete();
            // registered · updated · capitalised · depreciated · transferred · disposed
            $table->string('type', 30);
            $table->date('event_date');
            $table->string('from_location', 120)->nullable();
            $table->string('to_location', 120)->nullable();
            $table->foreignId('from_custodian_id')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('to_custodian_id')->nullable()->constrained('users')->nullOnDelete();
            $table->decimal('amount', 18, 2)->nullable();
            $table->string('notes', 500)->nullable();
            $table->foreignId('journal_entry_id')->nullable()->constrained('journal_entries')->nullOnDelete();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['fixed_asset_id', 'event_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('asset_events');
        Schema::dropIfExists('asset_depreciation_lines');
        Schema::dropIfExists('asset_depreciation_runs');
        Schema::dropIfExists('fixed_assets');
        Schema::dropIfExists('asset_classes');
    }
};
