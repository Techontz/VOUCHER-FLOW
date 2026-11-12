<?php

namespace App\Http\Controllers\Api\Platform;

use App\Http\Controllers\Controller;
use App\Http\Resources\InvoiceResource;
use App\Http\Resources\SubscriptionResource;
use App\Models\Company;
use App\Models\Invoice;
use App\Models\Subscription;
use App\Services\AuditLogger;
use App\Services\PaymentGateway;
use App\Services\Platform\SubscriptionAdmin;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/** Every subscription on the platform, and the operator's hand on each. */
class SubscriptionController extends Controller
{
    public function __construct(
        private readonly SubscriptionAdmin $admin,
        private readonly PaymentGateway $payments,
        private readonly AuditLogger $audit,
    ) {}

    public function index(Request $request)
    {
        $data = $request->validate([
            'q' => ['nullable', 'string', 'max:120'],
            'status' => ['nullable', Rule::in(['trialing', 'active', 'past_due', 'cancelled', 'expired', 'ending'])],
            'plan_id' => ['nullable', 'integer'],
            'company_id' => ['nullable', 'integer'],
            'expiring' => ['nullable', 'integer', 'min:1', 'max:365'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:200'],
        ]);

        $subscriptions = Subscription::query()
            ->withoutGlobalScopes()
            ->with(['plan', 'company'])
            ->when($data['status'] ?? null, fn ($q, $v) => $v === 'ending'
                ? $q->whereIn('status', SubscriptionAdmin::RUNNING)->where('cancel_at_period_end', true)
                : $q->where('status', $v))
            ->when($data['plan_id'] ?? null, fn ($q, $v) => $q->where('plan_id', $v))
            ->when($data['company_id'] ?? null, fn ($q, $v) => $q->where('company_id', $v))
            ->when($data['expiring'] ?? null, fn ($q, $v) => $q->whereIn('status', SubscriptionAdmin::RUNNING)
                ->whereBetween('current_period_end', [now(), now()->addDays((int) $v)]))
            ->when($data['q'] ?? null, fn ($q, $v) => $q->whereHas('company', fn ($c) => $c
                ->where('name', 'like', "%{$v}%")->orWhere('email', 'like', "%{$v}%")))
            // Running subscriptions first, then by when they end.
            ->orderByRaw("case when status in ('trialing','active','past_due') then 0 else 1 end")
            ->orderBy('current_period_end')
            ->orderByDesc('id')
            ->paginate((int) ($data['per_page'] ?? 25))
            ->withQueryString();

        // The newest unpaid invoice of each, so it can be settled from the list.
        $unpaid = Invoice::query()->withoutGlobalScopes()
            ->whereIn('subscription_id', $subscriptions->pluck('id'))
            ->whereIn('status', ['pending', 'failed'])
            ->orderByDesc('id')
            ->get()
            ->unique('subscription_id')
            ->keyBy('subscription_id');

        // And the newest paid one, so it can be refunded from the list.
        $lastPaid = Invoice::query()->withoutGlobalScopes()
            ->whereIn('subscription_id', $subscriptions->pluck('id'))
            ->where('status', 'paid')
            ->orderByDesc('id')
            ->get()
            ->unique('subscription_id')
            ->keyBy('subscription_id');

        $base = Subscription::query()->withoutGlobalScopes();

        return SubscriptionResource::collection($subscriptions)
            ->additional([
                'unpaid_invoices' => $unpaid->map(fn (Invoice $i) => new InvoiceResource($i)),
                'paid_invoices' => $lastPaid->map(fn (Invoice $i) => new InvoiceResource($i)),
                'summary' => [
                    'running' => (clone $base)->whereIn('status', SubscriptionAdmin::RUNNING)->count(),
                    'trialing' => (clone $base)->where('status', 'trialing')->count(),
                    'active' => (clone $base)->where('status', 'active')->count(),
                    'past_due' => (clone $base)->where('status', 'past_due')->count(),
                    'ending' => (clone $base)->whereIn('status', SubscriptionAdmin::RUNNING)->where('cancel_at_period_end', true)->count(),
                    'expiring_30' => (clone $base)->whereIn('status', SubscriptionAdmin::RUNNING)
                        ->whereBetween('current_period_end', [now(), now()->addDays(30)])->count(),
                ],
            ]);
    }

    public function extend(Request $request, Subscription $subscription)
    {
        $company = Company::findOrFail($subscription->company_id);

        abort_unless(
            in_array($subscription->status, SubscriptionAdmin::RUNNING, true),
            422,
            'Only a running subscription can be extended. Reactivate it first.',
        );

        $this->admin->extend($company, $this->until($request, $subscription->current_period_end));

        return new SubscriptionResource($subscription->fresh()->load(['plan', 'company']));
    }

    public function cancel(Request $request, Subscription $subscription)
    {
        $data = $request->validate(['when' => ['required', Rule::in(['period_end', 'immediately'])]]);

        $done = $this->admin->cancel($subscription, $data['when'] === 'immediately');

        return new SubscriptionResource($done->load(['plan', 'company']));
    }

    /** Raises an invoice for the current period, to be paid or marked paid. */
    public function invoice(Subscription $subscription)
    {
        abort_unless(
            in_array($subscription->status, SubscriptionAdmin::RUNNING, true),
            422,
            'Only a running subscription can be invoiced.',
        );

        abort_if(
            Invoice::query()->withoutGlobalScopes()->where('subscription_id', $subscription->id)->where('status', 'pending')->exists(),
            422,
            'This subscription already has an unpaid invoice.',
        );

        $company = Company::findOrFail($subscription->company_id);
        $invoice = $this->payments->issueInvoice($company, $subscription->load('plan'));

        $this->audit->log('platform.invoice_issued', "Issued {$invoice->number} to {$company->name}", $invoice, null, ['total' => (float) $invoice->total], $company->id);

        return (new InvoiceResource($invoice))->response()->setStatusCode(201);
    }

    public function reactivate(Subscription $subscription)
    {
        return new SubscriptionResource($this->admin->reactivate($subscription)->load(['plan', 'company']));
    }

    /**
     * The new end date: an explicit `until`, or `days` added to the current
     * end (or to today when that has already passed).
     */
    public static function until(Request $request, ?Carbon $current): Carbon
    {
        $data = $request->validate([
            'days' => ['required_without:until', 'nullable', 'integer', 'min:1', 'max:730'],
            'until' => ['required_without:days', 'nullable', 'date'],
        ]);

        if (! empty($data['until'])) {
            return Carbon::parse($data['until'])->endOfDay();
        }

        $from = $current && $current->isFuture() ? $current->copy() : now();

        return $from->addDays((int) $data['days']);
    }
}
