<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('companies', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('slug')->unique();
            $table->string('legal_name')->nullable();
            $table->string('email');
            $table->string('phone')->nullable();
            $table->string('address')->nullable();
            $table->string('website')->nullable();
            $table->char('country', 2)->default('TZ');
            $table->char('currency', 3)->default('TZS');
            $table->string('locale', 5)->default('en');
            $table->string('timezone')->default('Africa/Dar_es_Salaam');

            // Branding — applied to the interface and to every generated voucher.
            $table->string('logo_path')->nullable();
            $table->string('primary_color', 9)->default('#0088b0');
            $table->string('accent_color', 9)->default('#d6006c');
            $table->string('theme', 10)->default('dark');
            $table->text('voucher_footer_text')->nullable();

            $table->enum('status', ['trial', 'active', 'past_due', 'suspended', 'cancelled'])->default('trial');
            $table->foreignId('plan_id')->nullable()->constrained('plans')->nullOnDelete();
            $table->timestamp('trial_ends_at')->nullable();
            $table->timestamp('subscribed_at')->nullable();
            $table->timestamp('current_period_start')->nullable();
            $table->timestamp('current_period_end')->nullable();
            $table->boolean('auto_renew')->default(true);

            $table->json('settings')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('companies');
    }
};
