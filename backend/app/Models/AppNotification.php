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
        return [
            'read_at' => 'datetime',

            /*
             * Integer columns are cast because they are compared with === in
             * PHP. MySQL returns them as strings under emulated prepared
             * statements, where "8" === 8 is false — which silently turned an
             * owner into a stranger and a matching id into a mismatch.
             */
            'company_id' => 'integer',
            'user_id' => 'integer',
            'entity_id' => 'integer',
        ];
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
