<?php

namespace App\Support;

use App\Models\PlatformSetting;
use Illuminate\Support\Facades\Schema;

/**
 * Platform-wide defaults the operator can change from the platform settings
 * page: the trial a new company gets when its plan names none, the support
 * address shown to tenants and the currency a new company starts in.
 *
 * Each falls back to its config value, so a fresh install (or a database not
 * yet migrated) behaves exactly as it did before the table existed.
 */
class PlatformSettings
{
    /** @var array<string, array{rules: list<string>, default: callable(): mixed}> */
    public static function definitions(): array
    {
        return [
            'trial_days' => [
                'rules' => ['integer', 'min:0', 'max:365'],
                'default' => fn () => (int) config('vouchflow.trial_days', 14),
            ],
            'support_email' => [
                'rules' => ['nullable', 'email', 'max:180'],
                'default' => fn () => config('mail.from.address'),
            ],
            'default_currency' => [
                'rules' => ['string', 'size:3'],
                'default' => fn () => 'TZS',
            ],
        ];
    }

    /** Held in the container, not a static, so it lives exactly as long as the request (or test). */
    private const CACHE = 'platform.settings';

    /** @return array<string, mixed> */
    public static function all(): array
    {
        if (! app()->bound(self::CACHE)) {
            $stored = Schema::hasTable('platform_settings')
                ? PlatformSetting::query()->pluck('value', 'key')->all()
                : [];

            $values = [];
            foreach (self::definitions() as $key => $definition) {
                $values[$key] = array_key_exists($key, $stored) && $stored[$key] !== null
                    ? $stored[$key]
                    : ($definition['default'])();
            }

            app()->instance(self::CACHE, $values);
        }

        return app(self::CACHE);
    }

    public static function get(string $key): mixed
    {
        return self::all()[$key] ?? null;
    }

    /** @param  array<string, mixed>  $values */
    public static function put(array $values): void
    {
        foreach ($values as $key => $value) {
            if (! array_key_exists($key, self::definitions())) {
                continue;
            }

            PlatformSetting::updateOrCreate(['key' => $key], ['value' => $value]);
        }

        self::flush();
    }

    public static function flush(): void
    {
        app()->forgetInstance(self::CACHE);
    }

    public static function trialDays(): int
    {
        return (int) self::get('trial_days');
    }

    public static function currency(): string
    {
        return strtoupper((string) self::get('default_currency'));
    }
}
