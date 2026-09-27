<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The second step of a sign-in. A row exists between a correct password and
     * a correct one-time code; only hashes of the challenge id and the code are
     * stored.
     */
    public function up(): void
    {
        Schema::create('login_challenges', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('token_hash', 64)->unique();
            $table->enum('channel', ['email', 'sms'])->nullable();
            $table->string('code_hash')->nullable();
            $table->dateTime('code_sent_at')->nullable();
            $table->dateTime('code_expires_at')->nullable();
            $table->unsignedTinyInteger('sends')->default(0);
            $table->unsignedTinyInteger('attempts')->default(0);
            $table->string('ip', 45)->nullable();
            $table->dateTime('expires_at');
            $table->dateTime('consumed_at')->nullable();
            $table->timestamps();

            $table->index(['user_id', 'consumed_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('login_challenges');
    }
};
