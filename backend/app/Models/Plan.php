<?php

namespace App\Models;

use App\Support\Erp\BusinessTemplates;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use RuntimeException;

class Plan extends Model
{
    use HasFactory;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            /*
             * Integer columns are cast because they are compared with === in
             * PHP. MySQL returns them as strings under emulated prepared
             * statements, where "8" === 8 is false, which silently turned an
             * owner into a stranger and a matching id into a mismatch.
             */
            'max_users' => 'integer',
            'max_vouchers_per_month' => 'integer',
            'max_departments' => 'integer',
            'max_approval_levels' => 'integer',
            'storage_mb' => 'integer',
            'trial_days' => 'integer',
            'sort_order' => 'integer',
            'price' => 'decimal:2',
            'price_yearly' => 'decimal:2',
            'features' => 'array',
            'modules' => 'array',
            'is_featured' => 'boolean',
            'allows_module_choice' => 'boolean',
            'price_per_module' => 'decimal:2',
            'is_active' => 'boolean',
            'is_public' => 'boolean',
        ];
    }

    public function companies(): HasMany
    {
        return $this->hasMany(Company::class);
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(Subscription::class);
    }

    /** The price of a year: its own when set, otherwise ten months, the discount shown on pricing. */
    public function yearlyPrice(): float
    {
        return $this->price_yearly !== null ? (float) $this->price_yearly : (float) $this->price * 10;
    }

    /**
     * The apps this plan offers: the ones it lists, or every app when it
     * lists none. VouchFlow is always one of them.
     *
     * @return list<string>
     */
    public function apps(): array
    {
        $all = array_keys(BusinessTemplates::modules());

        if (empty($this->modules)) {
            return $all;
        }

        return array_values(array_intersect($all, ['vouchflow', ...$this->modules]));
    }

    public function includesAllApps(): bool
    {
        return count($this->apps()) === count(BusinessTemplates::modules());
    }

    /**
     * What a subscription to this plan costs for a period.
     *
     * A bundle costs its price whatever apps are used. A pick-your-apps plan
     * costs its base price plus the price per app for each app chosen,
     * VouchFlow excepted since every plan includes it; a year is the yearly
     * base plus ten months of each app, the discount pricing shows.
     *
     * @param  list<string>|null  $apps  the chosen apps; null means all the plan offers
     */
    public function priceFor(?array $apps, string $cycle): float
    {
        $annual = $cycle === 'annual';
        $base = $annual ? $this->yearlyPrice() : (float) $this->price;

        if (! $this->allows_module_choice) {
            return $base;
        }

        $chosen = array_diff(array_intersect($apps ?? $this->apps(), $this->apps()), ['vouchflow']);
        $perApp = (float) $this->price_per_module * ($annual ? 10 : 1);

        return round($base + $perApp * count($chosen), 2);
    }

    /**
     * Refuses apps this plan does not offer, for a customer choosing their
     * own. The platform may license apps beyond a plan; a customer may not.
     *
     * @param  list<string>  $apps
     */
    public function assertOffers(array $apps): void
    {
        $outside = array_values(array_diff($apps, $this->apps()));

        if ($outside) {
            $catalogue = BusinessTemplates::modules();
            $labels = array_map(fn (string $m) => $catalogue[$m]['label'] ?? $m, $outside);

            throw new RuntimeException(
                implode(', ', $labels).(count($labels) === 1 ? ' is' : ' are')." not part of the {$this->name} plan. Choose a plan that includes "
                .(count($labels) === 1 ? 'it' : 'them').'.'
            );
        }
    }

    public function isUnlimited(string $limit): bool
    {
        return $this->{$limit} === null;
    }
}
