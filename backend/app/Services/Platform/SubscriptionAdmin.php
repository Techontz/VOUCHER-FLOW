<?php

namespace App\Services\Platform;

use App\Models\Company;
use App\Models\Subscription;
use App\Services\AuditLogger;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * What the platform operator does to a company's billing by hand: give it
 * more time, cancel it (at the end of the period or now) and bring a
 * cancelled one back. No money moves here; payments go through
 * PaymentGateway. The company row mirrors the running subscription's dates,
 * so every change here writes both.
 */
class SubscriptionAdmin
{
    public const RUNNING = ['trialing', 'active', 'past_due'];

    public function __construct(private readonly AuditLogger $audit) {}

    /** The subscription a company is on now, if any. */
    public function running(Company $company): ?Subscription
    {
        return Subscription::query()->withoutGlobalScopes()
            ->where('company_id', $company->id)
            ->whereIn('status', self::RUNNING)
            ->latest('id')
            ->first();
    }

    /**
     * Moves the end of a company's trial or paid period to $until.
     *
     * A pending company has no period yet (approve it first) and a cancelled
     * one must be reactivated, extending either would only hide the state it
     * is in. A suspension stays: more time does not lift it.
     */
    public function extend(Company $company, Carbon $until): Company
    {
        if ($company->isPending()) {
            throw new RuntimeException('Approve this company before extending its subscription.');
        }

        if ($company->status === 'cancelled') {
            throw new RuntimeException('This subscription is cancelled. Reactivate it instead of extending it.');
        }

        if ($until->isPast()) {
            throw new RuntimeException('The new end date must be in the future.');
        }

        $trial = $company->status === 'trial';
        $current = $trial ? $company->trial_ends_at : $company->current_period_end;

        if ($current && $until->lte($current)) {
            throw new RuntimeException('The new end date must be later than the current one, '.$current->toDateString().'.');
        }

        $before = $this->dates($company);

        DB::transaction(function () use ($company, $until, $trial) {
            $subscription = $this->running($company);

            if ($subscription) {
                $subscription->forceFill(array_filter([
                    'current_period_end' => $until,
                    'trial_ends_at' => $subscription->status === 'trialing' ? $until : null,
                    // Time given covers what was overdue.
                    'status' => $subscription->status === 'past_due' ? 'active' : null,
                ]))->save();
            }

            $company->forceFill(array_filter([
                'current_period_end' => $until,
                'trial_ends_at' => $trial ? $until : null,
                'status' => $company->status === 'past_due' ? 'active' : null,
            ]))->save();
        });

        $this->audit->log(
            'platform.subscription_extended',
            "Extended {$company->name} to {$until->toDateString()}",
            $company, $before, $this->dates($company->fresh()), $company->id,
        );

        return $company->fresh();
    }

    /**
     * Cancels a running subscription: at the end of the period (it keeps
     * working until then and does not renew) or immediately (the company
     * loses access now).
     */
    public function cancel(Subscription $subscription, bool $immediately): Subscription
    {
        if (! in_array($subscription->status, self::RUNNING, true)) {
            throw new RuntimeException('Only a running subscription can be cancelled.');
        }

        if (! $immediately && $subscription->cancel_at_period_end) {
            throw new RuntimeException('This subscription is already set to end with its period.');
        }

        $company = Company::findOrFail($subscription->company_id);
        $before = ['status' => $subscription->status, 'cancel_at_period_end' => (bool) $subscription->cancel_at_period_end];

        DB::transaction(function () use ($subscription, $company, $immediately) {
            if ($immediately) {
                $subscription->forceFill([
                    'status' => 'cancelled',
                    'cancelled_at' => now(),
                    'current_period_end' => now(),
                    'cancel_at_period_end' => false,
                ])->save();

                $company->forceFill([
                    'status' => 'cancelled',
                    'auto_renew' => false,
                    'current_period_end' => now(),
                ])->save();

                return;
            }

            $subscription->forceFill(['cancel_at_period_end' => true])->save();
            $company->forceFill(['auto_renew' => false])->save();
        });

        $this->audit->log(
            $immediately ? 'platform.subscription_cancelled' : 'platform.subscription_cancel_scheduled',
            $immediately
                ? "Cancelled {$company->name}'s subscription immediately"
                : "Set {$company->name}'s subscription to end on ".($subscription->current_period_end?->toDateString() ?? 'its period end'),
            $subscription,
            $before,
            ['status' => $subscription->status, 'cancel_at_period_end' => (bool) $subscription->cancel_at_period_end],
            $company->id,
        );

        return $subscription->fresh();
    }

    /**
     * Undoes a cancellation. A subscription only set to end with its period
     * simply carries on; one already cancelled or expired starts a fresh
     * period of its billing cycle from today, provided the company is not on
     * another subscription meanwhile.
     */
    public function reactivate(Subscription $subscription): Subscription
    {
        $company = Company::findOrFail($subscription->company_id);
        $before = ['status' => $subscription->status, 'cancel_at_period_end' => (bool) $subscription->cancel_at_period_end];

        if (in_array($subscription->status, self::RUNNING, true)) {
            if (! $subscription->cancel_at_period_end) {
                throw new RuntimeException('This subscription is running and not cancelled.');
            }

            DB::transaction(function () use ($subscription, $company) {
                $subscription->forceFill(['cancel_at_period_end' => false])->save();
                $company->forceFill(['auto_renew' => true])->save();
            });
        } else {
            $other = $this->running($company);

            if ($other && $other->id !== $subscription->id) {
                throw new RuntimeException("{$company->name} is already on another subscription. Change its plan instead.");
            }

            if ($company->isPending()) {
                throw new RuntimeException('Approve this company before reactivating its subscription.');
            }

            $start = now();
            $end = $subscription->billing_cycle === 'annual' ? $start->copy()->addYear() : $start->copy()->addMonth();

            DB::transaction(function () use ($subscription, $company, $start, $end) {
                $subscription->forceFill([
                    'status' => 'active',
                    'cancelled_at' => null,
                    'cancel_at_period_end' => false,
                    'current_period_start' => $start,
                    'current_period_end' => $end,
                ])->save();

                $company->forceFill([
                    'plan_id' => $subscription->plan_id,
                    // A suspension is lifted only by activating the company.
                    'status' => $company->status === 'suspended' ? 'suspended' : 'active',
                    'auto_renew' => true,
                    'subscribed_at' => $company->subscribed_at ?? $start,
                    'current_period_start' => $start,
                    'current_period_end' => $end,
                ])->save();
            });
        }

        $this->audit->log(
            'platform.subscription_reactivated',
            "Reactivated {$company->name}'s subscription",
            $subscription,
            $before,
            ['status' => $subscription->status, 'cancel_at_period_end' => (bool) $subscription->cancel_at_period_end],
            $company->id,
        );

        return $subscription->fresh();
    }

    /** @return array<string, string|null> */
    private function dates(Company $company): array
    {
        return [
            'status' => $company->status,
            'trial_ends_at' => $company->trial_ends_at?->toDateString(),
            'current_period_end' => $company->current_period_end?->toDateString(),
        ];
    }
}
