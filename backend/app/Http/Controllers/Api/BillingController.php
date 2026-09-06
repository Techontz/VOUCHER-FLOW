<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\InvoiceResource;
use App\Http\Resources\PlanResource;
use App\Http\Resources\SubscriptionResource;
use App\Models\Invoice;
use App\Models\Plan;
use App\Services\AuditLogger;
use App\Services\PaymentGateway;
use App\Services\UsageLimits;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** The tenant's own subscription, usage, invoices and payments. */
class BillingController extends Controller
{
    public function __construct(
        private readonly PaymentGateway $payments,
        private readonly UsageLimits $limits,
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    /** Public: the pricing table on the landing page. */
    public function plans()
    {
        return PlanResource::collection(
            Plan::where('is_active', true)->where('is_public', true)->orderBy('sort_order')->get()
        );
    }

    public function subscription(Request $request)
    {
        $company = $this->tenant->company();
        abort_unless($company, 404, 'No company context.');

        $subscription = $company->activeSubscription();

        return response()->json([
            'subscription' => $subscription ? new SubscriptionResource($subscription->load('plan')) : null,
            'plan' => $company->plan ? new PlanResource($company->plan) : null,
            'usage' => $this->limits->snapshot($company),
            'company_status' => $company->status,
            'is_expired' => $company->isExpired(),
            'days_remaining' => $company->daysRemaining(),
            'auto_renew' => (bool) $company->auto_renew,
            'available_plans' => PlanResource::collection(
                Plan::where('is_active', true)->orderBy('sort_order')->get()
            ),
        ]);
    }

    public function invoices(Request $request)
    {
        $this->authorizeAdmin($request);

        $invoices = Invoice::query()
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->latest('id')
            ->paginate((int) $request->query('per_page', 20));

        return InvoiceResource::collection($invoices);
    }

    /** Changes plan and issues the invoice for the new period. */
    public function subscribe(Request $request)
    {
        $this->authorizeAdmin($request);

        $data = $request->validate([
            'plan_id' => ['required', 'integer', Rule::exists('plans', 'id')->where('is_active', true)],
            'billing_cycle' => ['nullable', Rule::in(['monthly', 'annual'])],
        ]);

        $company = $this->tenant->company();
        $plan = Plan::findOrFail($data['plan_id']);
        $cycle = $data['billing_cycle'] ?? $plan->billing_cycle;

        // Downgrading below current usage would silently break the tenant.
        if ($plan->max_users !== null) {
            $seats = $company->users()->count();

            abort_if(
                $seats > $plan->max_users,
                422,
                "The {$plan->name} plan allows {$plan->max_users} users and {$seats} are in use. Remove users before downgrading.",
            );
        }

        $subscription = $this->payments->subscribe($company, $plan, $cycle);
        $invoice = $this->payments->issueInvoice($company, $subscription);

        return response()->json([
            'message' => "Subscribed to the {$plan->name} plan.",
            'subscription' => new SubscriptionResource($subscription->load('plan')),
            'invoice' => new InvoiceResource($invoice),
        ], 201);
    }

    public function pay(Request $request, Invoice $invoice)
    {
        $this->authorizeAdmin($request);

        $data = $request->validate([
            'method' => ['required', Rule::in(['mobile_money', 'card', 'bank_transfer'])],
            'reference' => ['nullable', 'string', 'max:60'],
        ]);

        $paid = $this->payments->charge($invoice, $data);

        return response()->json([
            'message' => 'Payment successful. Your receipt is available in the billing history.',
            'invoice' => new InvoiceResource($paid),
        ]);
    }

    public function setAutoRenew(Request $request)
    {
        $this->authorizeAdmin($request);

        $data = $request->validate(['auto_renew' => ['required', 'boolean']]);

        $company = $this->tenant->company();
        $company->forceFill(['auto_renew' => $data['auto_renew']])->save();

        $this->audit->log(
            'subscription.auto_renew',
            $data['auto_renew'] ? 'Enabled auto-renew' : 'Disabled auto-renew',
            $company,
        );

        return response()->json(['auto_renew' => (bool) $company->auto_renew]);
    }

    private function authorizeAdmin(Request $request): void
    {
        abort_unless($request->user()->isAdmin(), 403, 'Only an administrator may manage billing.');
    }
}
