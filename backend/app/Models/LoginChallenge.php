<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class LoginChallenge extends Model
{
    protected $guarded = ['id'];

    protected $hidden = ['token_hash', 'code_hash'];

    protected function casts(): array
    {
        return [
            'code_sent_at' => 'datetime',
            'code_expires_at' => 'datetime',
            'expires_at' => 'datetime',
            'consumed_at' => 'datetime',
            'sends' => 'integer',
            'attempts' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** Looks up a live challenge by the opaque id the client holds. */
    public static function findByToken(string $token): ?self
    {
        return static::where('token_hash', hash('sha256', $token))->first();
    }

    public function isOpen(): bool
    {
        return $this->consumed_at === null && $this->expires_at->isFuture();
    }
}
