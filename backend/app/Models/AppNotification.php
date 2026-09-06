<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AppNotification extends Model
{
    use HasFactory;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return ['read_at' => 'datetime'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function company(): BelongsTo
    {
        return $this->belongsTo(Company::class);
    }

    public function isUnread(): bool
    {
        return $this->read_at === null;
    }

    public function title(string $locale = 'en'): string
    {
        return $locale === 'sw' && $this->title_sw ? $this->title_sw : $this->title;
    }

    public function body(string $locale = 'en'): ?string
    {
        return $locale === 'sw' && $this->body_sw ? $this->body_sw : $this->body;
    }
}
