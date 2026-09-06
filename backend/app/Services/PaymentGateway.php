<?php

namespace App\Services;

use App\Models\Company;
use App\Models\Invoice;
use App\Models\Plan;
use App\Models\Subscription;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Subscription billing and online payment capture.
 *
 * The `demo` driver settles deterministically so the whole billing flow — invoice,
 * charge, receipt, period roll-forward, expiry — is exercisable end to end. Swap
 * in a real PSP by implementing charge() against its API; nothing else changes.
 */
class PaymentGateway
{
    public function __construct(private readonly AuditLogger $audit) {}

    public function driver(): string
    {
        return (string) config('vouchflow.payments_driver', 'demo');
    }

    /** Starts (or changes to) a plan, issuing the first invoice. */
    public function subscribe(Company $company, Plan $plan, string $cycle = 'monthly'): Subscription
    {
        return DB::transaction(function () use ($company, $plan, $cycle) {
            $amount = $this->amountFor($plan, $cycle);
            $periodStart = now();
            $periodEnd = $cycle === 'annual' ? now()->addYear() : now()->addMonth();

            // Close any subscription still running.
            Subscription::where('company_id', $company->id)
                ->whereIn('status', ['trialing', 'active', 'past_due'])
                ->update(['status' => 'cancelled', 'cancelled_at' => now()]);

            $subscription = Subscription::create([
                'company_id' => $company->id,
                'plan_id' => $plan->id,
                'status' => 'active',
                'billing_cycle' => $cycle,
                'amount' => $amount,
                'currency' => $plan->currency,
                'seats' => $plan->max_users,
                'starts_at' => $periodStart,
                'current_period_start' => $periodStart,
                'current_period_end' => $periodEnd,
            ]);

            $company->forceFill([
                'plan_id' => $plan->id,
                'status' => 'active',
                'subscribed_at' => $periodStart,
                'current_period_start' => $periodStart,
                'current_period_end' => $periodEnd,
            ])->save();

            $this->audit->log('subscription.changed', "Subscribed to the {$plan->name} plan", $company);

            return $subscription;
        });
    }

    /** Puts a company on its plan's free trial without taking payment. */
    public function startTrial(Company $company, Plan $plan): Subscription
    {
        $trialEnds = now()->addDays((int) ($plan->trial_days ?: config('vouchflow.trial_days', 14)));

        $subscription = Subscription::create([
            'company_id' => $company->id,
            'plan_id' => $plan->id,
            'status' => 'trialing',
            'billing_cycle' => $plan->billing_cycle,
            'amount' => $plan->price,
            'currency' => $plan->currency,
            'seats' => $plan->max_users,
            'starts_at' => now(),
            'trial_ends_at' => $trialEnds,
            'current_period_start' => now(),
            'current_period_end' => $trialEnds,
        ]);

        $company->forceFill([
            'plan_id' => $plan->id,
            'status' => 'trial',
            'trial_ends_at' => $trialEnds,
            'current_period_start' => now(),
            'current_period_end' => $trialEnds,
        ])->save();

        return $subscription;
    }

    public function issueInvoice(Company $company, Subscription $subscription, ?string $description = null): Invoice
    {
        $cycleLabel = $subscription->billing_cycle === 'annual' ? 'annual' : 'monthly';

        return Invoice::create([
            'company_id' => $company->id,
            'subscription_id' => $subscription->id,
            'number' => $this->invoiceNumber(),
            'description' => $description ?: "{$subscription->plan->name} · {$cycleLabel}",
            'amount' => $subscription->amount,
            'tax' => 0,
            'total' => $subscription->amount,
            'currency' => $subscription->currency,
            'status' => 'pending',
            'period_start' => $subscription->current_period_start,
            'period_end' => $subscription->current_period_end,
            'issued_at' => now(),
        ]);
    }

    /**
     * Captures payment for an invoice.
     *
     * @param  array{method:string,reference?:string}  $payload
     */
    public function charge(Invoice $invoice, array $payload): Invoice
    {
        if ($invoice->isPaid()) {
            throw new RuntimeException('This invoice has already been paid.');
        }

        $method = $payload['method'] ?? 'mobile_money';
        $reference = $payload['reference'] ?? null;

        if (! in_array($method, ['mobile_money', 'card', 'bank_transfer'], true)) {
            throw new RuntimeException('Unsupported payment method.');
        }

        if ($method !== 'bank_transfer' && ! $reference) {
            throw new RuntimeException('A mobile money number or card reference is required.');
        }

        $result = $this->authorise($method, $reference, (float) $invoice->total, $invoice->currency);

        // A decline is recorded outside the transaction: throwing inside it would
        // roll the "failed" status straight back, losing the attempt.
        if (! $result['approved']) {
            $invoice->forceFill([
                'status' => 'failed',
                'method' => $method,
                'provider' => $this->driver(),
                'payer_reference' => $reference,
                'failure_reason' => $result['message'],
            ])->save();

            $this->audit->log('payment.failed', "Payment failed for {$invoice->number}: {$result['message']}", $invoice);

            throw new RuntimeException($result['message']);
        }

        return DB::transaction(function () use ($invoice, $method, $reference, $result) {
            $invoice->forceFill([
                'status' => 'paid',
                'method' => $method,
                'provider' => $this->driver(),
                'provider_ref' => $result['reference'],
                'payer_reference' => $reference,
                'paid_at' => now(),
                'failure_reason' => null,
            ])->save();

            $this->settle($invoice);

            $this->audit->log('payment.succeeded', "Payment received for {$invoice->number}", $invoice);

            return $invoice->fresh();
        });
    }

    /** Rolls the subscription period forward once an invoice is paid. */
    private function settle(Invoice $invoice): void
    {
        $subscription = $invoice->subscription;

        if (! $subscription) {
            return;
        }

        $start = $subscription->current_period_end && $subscription->current_period_end->isFuture()
            ? $subscription->current_period_end
            : now();

        $end = $subscription->billing_cycle === 'annual' ? $start->copy()->addYear() : $start->copy()->addMonth();

        $subscription->forceFill([
            'status' => 'active',
            'current_period_start' => $start,
            'current_period_end' => $end,
        ])->save();

        $company = $invoice->company ?? Company::find($invoice->company_id);

        $company?->forceFill([
            'status' => 'active',
            'current_period_start' => $start,
            'current_period_end' => $end,
        ])->save();
    }

    public function refund(Invoice $invoice, ?string $reason = null): Invoice
    {
        if (! $invoice->isPaid()) {
            throw new RuntimeException('Only a paid invoice can be refunded.');
        }

        $invoice->forceFill(['status' => 'refunded', 'failure_reason' => $reason])->save();
        $this->audit->log('payment.refunded', "Refunded {$invoice->number}", $invoice);

        return $invoice->fresh();
    }

    private function authorise(string $method, ?string $reference, float $amount, string $currency): array
    {
        if ($this->driver() !== 'demo') {
            throw new RuntimeException('No live payment provider is configured.');
        }

        // Deterministic sandbox: a reference ending in 0000 declines, so the
        // failure path is testable without waiting on a real gateway timeout.
        if ($reference && str_ends_with(preg_replace('/\D/', '', $reference), '0000')) {
            return ['approved' => false, 'message' => 'The payment was declined by the provider. No money left the account.', 'reference' => null];
        }

        return [
            'approved' => true,
            'message' => 'Approved',
            'reference' => strtoupper($this->driver()).'-'.now()->format('YmdHis').'-'.random_int(1000, 9999),
        ];
    }

    private function amountFor(Plan $plan, string $cycle): float
    {
        // Annual billing is charged at ten months, the discount shown on pricing.
        return $cycle === 'annual' ? (float) $plan->price * 10 : (float) $plan->price;
    }

    public function invoiceNumber(): string
    {
        $year = now()->format('Y');
        $count = Invoice::query()->withoutGlobalScopes()->whereYear('created_at', $year)->count() + 1;

        return sprintf('INV-%s-%04d', $year, $count);
    }
}
