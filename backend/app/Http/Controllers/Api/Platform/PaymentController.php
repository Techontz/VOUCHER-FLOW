<?php

namespace App\Http\Controllers\Api\Platform;

use App\Http\Controllers\Controller;
use App\Http\Resources\InvoiceResource;
use App\Http\Resources\SubscriptionResource;
use App\Models\Invoice;
use App\Models\Subscription;
use App\Services\PaymentGateway;
use Illuminate\Http\Request;

/** Platform-wide payment and subscription oversight. */
class PaymentController extends Controller
{
    public function __construct(private readonly PaymentGateway $payments) {}

    public function index(Request $request)
    {
        $invoices = Invoice::query()
            ->withoutGlobalScopes()
            ->with('company')
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('company_id'), fn ($q, $v) => $q->where('company_id', $v))
            ->when($request->query('method'), fn ($q, $v) => $q->where('method', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                ->where('number', 'like', "%{$v}%")
                ->orWhereHas('company', fn ($c) => $c->where('name', 'like', "%{$v}%"))))
            ->latest('id')
            ->paginate((int) $request->query('per_page', 25))
            ->withQueryString();

        return InvoiceResource::collection($invoices)->additional([
            'meta' => [
                'collected' => (float) Invoice::query()->withoutGlobalScopes()->where('status', 'paid')->sum('total'),
                'outstanding' => (float) Invoice::query()->withoutGlobalScopes()->whereIn('status', ['pending', 'failed'])->sum('total'),
            ],
        ]);
    }

    public function subscriptions(Request $request)
    {
        $subscriptions = Subscription::query()
            ->withoutGlobalScopes()
            ->with(['plan', 'company'])
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->latest('id')
            ->paginate((int) $request->query('per_page', 25));

        return SubscriptionResource::collection($subscriptions);
    }

    public function refund(Request $request, Invoice $invoice)
    {
        $data = $request->validate(['reason' => ['nullable', 'string', 'max:255']]);

        return new InvoiceResource($this->payments->refund($invoice, $data['reason'] ?? null));
    }

    /** Marks an off-platform payment (bank transfer) as settled. */
    public function markPaid(Request $request, Invoice $invoice)
    {
        $data = $request->validate([
            'reference' => ['nullable', 'string', 'max:60'],
        ]);

        $paid = $this->payments->charge($invoice, [
            'method' => 'bank_transfer',
            'reference' => $data['reference'] ?? null,
        ]);

        return new InvoiceResource($paid);
    }
}
