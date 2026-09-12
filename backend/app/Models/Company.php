<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;

class Company extends Model
{
    use HasFactory, SoftDeletes;

    protected $guarded = ['id'];

    /**
     * The editable profile, in one place.
     *
     * Controllers derive their validation from this rather than each keeping
     * its own list: the company form is filled in from three different places
     * (registration, the platform's create-company screen, and a tenant's own
     * settings) and three copies of the field list is three chances to accept a
     * field in one and silently drop it in another.
     *
     * Logos are excluded deliberately — a file is not a text field and goes
     * through its own validated upload path.
     */
    public const PROFILE_RULES = [
        'name' => ['string', 'max:180'],
        'legal_name' => ['nullable', 'string', 'max:180'],
        'trading_name' => ['nullable', 'string', 'max:180'],

        'email' => ['email', 'max:180'],
        'phone' => ['nullable', 'string', 'max:40'],
        'alternative_phone' => ['nullable', 'string', 'max:40'],
        'website' => ['nullable', 'string', 'max:180'],

        'address' => ['nullable', 'string', 'max:255'],
        'postal_address' => ['nullable', 'string', 'max:255'],
        'city' => ['nullable', 'string', 'max:120'],
        'region' => ['nullable', 'string', 'max:120'],
        'country' => ['nullable', 'string', 'size:2'],

        'tin' => ['nullable', 'string', 'max:40'],
        'registration_number' => ['nullable', 'string', 'max:60'],
        'business_license_number' => ['nullable', 'string', 'max:80'],

        'contact_person' => ['nullable', 'string', 'max:180'],
        'contact_email' => ['nullable', 'email', 'max:180'],
        'contact_phone' => ['nullable', 'string', 'max:40'],

        'bank_name' => ['nullable', 'string', 'max:120'],
        'bank_account_name' => ['nullable', 'string', 'max:180'],
        'bank_account_number' => ['nullable', 'string', 'max:64'],
        'bank_branch' => ['nullable', 'string', 'max:120'],
        'swift_code' => ['nullable', 'string', 'max:24'],

        'currency' => ['nullable', 'string', 'size:3'],
        'timezone' => ['nullable', 'string', 'max:60'],
    ];

    /** Colours, theme and the words printed on a voucher. */
    public const BRANDING_RULES = [
        'primary_color' => ['nullable', 'string', 'regex:/^#[0-9a-fA-F]{6}$/'],
        'secondary_color' => ['nullable', 'string', 'regex:/^#[0-9a-fA-F]{6}$/'],
        'accent_color' => ['nullable', 'string', 'regex:/^#[0-9a-fA-F]{6}$/'],
        'voucher_header_text' => ['nullable', 'string', 'max:255'],
        'voucher_footer_text' => ['nullable', 'string', 'max:500'],
    ];

    /**
     * What an uploaded logo may be.
     *
     * `image` alone is not enough: it accepts SVG, which is a script container.
     * The list is explicit, and the same list is enforced on both slots.
     */
    public static function logoRules(): array
    {
        return [
            'file', 'image', 'mimes:png,jpg,jpeg,webp', 'max:'.self::LOGO_MAX_KB,
            'dimensions:max_width=4000,max_height=4000',
        ];
    }

    public const LOGO_MAX_KB = 2048;

    /** Field rules for a write that must supply everything (create). */
    public static function creationRules(): array
    {
        $rules = self::PROFILE_RULES;
        $rules['name'] = ['required', ...$rules['name']];
        $rules['email'] = ['required', ...$rules['email']];

        return $rules + self::BRANDING_RULES;
    }

    /** Field rules for a partial write (update). */
    public static function updateRules(): array
    {
        $rules = [];

        foreach (self::PROFILE_RULES + self::BRANDING_RULES as $field => $rule) {
            $rules[$field] = ['sometimes', ...$rule];
        }

        $rules['locale'] = ['sometimes', 'nullable', Rule::in(config('vouchflow.locales'))];
        $rules['theme'] = ['sometimes', 'nullable', Rule::in(['light', 'dark'])];
        $rules['settings'] = ['sometimes', 'nullable', 'array'];

        return $rules;
    }

    /**
     * A public URL for a stored logo, or null.
     *
     * Kept on the model so the API resource, the PDF service and any future
     * consumer resolve a path the same way — and so a tenant that has never
     * uploaded anything returns null rather than a broken URL.
     */
    public function logoUrl(): ?string
    {
        return $this->fileUrl($this->logo_path);
    }

    /**
     * The square mark, for avatars and favicons.
     *
     * Falls back to the lockup so a tenant that uploaded only one still renders
     * something; the interface decides how to fit it.
     */
    public function logoMarkUrl(): ?string
    {
        return $this->fileUrl($this->logo_mark_path) ?? $this->logoUrl();
    }

    private function fileUrl(?string $path): ?string
    {
        if (! $path) {
            return null;
        }

        // A tenant may have been seeded with a path whose file was never
        // published; a missing file should read as "no logo", not as a 404 on
        // every page that renders the letterhead.
        return Storage::disk('public')->exists($path)
            ? Storage::disk('public')->url($path)
            : null;
    }

    /** Initials for the fallback mark, when a tenant has no artwork at all. */
    public function initials(): string
    {
        return collect(preg_split('/\s+/', trim((string) ($this->trading_name ?: $this->name))))
            ->filter(fn ($word) => (bool) preg_match('/[A-Za-z0-9]/', $word))
            ->take(2)
            ->map(fn ($word) => mb_strtoupper(mb_substr($word, 0, 1)))
            ->implode('');
    }

    /** The name that belongs on a legal document, falling back sensibly. */
    public function documentName(): string
    {
        return $this->legal_name ?: $this->name;
    }

    protected function casts(): array
    {
        return [
            /*
             * Integer columns are cast because they are compared with === in
             * PHP. MySQL returns them as strings under emulated prepared
             * statements, where "8" === 8 is false — which silently turned an
             * owner into a stranger and a matching id into a mismatch.
             */
            'plan_id' => 'integer',
            'trial_ends_at' => 'datetime',
            'subscribed_at' => 'datetime',
            'current_period_start' => 'datetime',
            'current_period_end' => 'datetime',
            'auto_renew' => 'boolean',
            'settings' => 'array',
        ];
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(Plan::class);
    }

    public function users(): HasMany
    {
        return $this->hasMany(User::class);
    }

    public function departments(): HasMany
    {
        return $this->hasMany(Department::class);
    }

    public function voucherTypes(): HasMany
    {
        return $this->hasMany(VoucherType::class);
    }

    public function workflows(): HasMany
    {
        return $this->hasMany(Workflow::class);
    }

    public function vouchers(): HasMany
    {
        return $this->hasMany(Voucher::class);
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(Subscription::class);
    }

    public function invoices(): HasMany
    {
        return $this->hasMany(Invoice::class);
    }

    public function activeSubscription(): ?Subscription
    {
        return $this->subscriptions()
            ->whereIn('status', ['trialing', 'active', 'past_due'])
            ->latest('id')
            ->first();
    }

    /** Whether the tenant may currently use the product. */
    public function isUsable(): bool
    {
        if (in_array($this->status, ['suspended', 'cancelled'], true)) {
            return false;
        }

        if ($this->status === 'trial' && $this->trial_ends_at && $this->trial_ends_at->isPast()) {
            return false;
        }

        return true;
    }

    public function isExpired(): bool
    {
        if ($this->status === 'trial') {
            return $this->trial_ends_at !== null && $this->trial_ends_at->isPast();
        }

        return $this->current_period_end !== null && $this->current_period_end->isPast();
    }

    public function daysRemaining(): ?int
    {
        $end = $this->status === 'trial' ? $this->trial_ends_at : $this->current_period_end;

        return $end ? max(0, now()->diffInDays($end, false)) : null;
    }
}
