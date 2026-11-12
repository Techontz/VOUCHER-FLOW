<?php

namespace App\Http\Controllers\Api\Platform;

use App\Http\Controllers\Controller;
use App\Models\Company;
use App\Models\Invoice;
use App\Models\Plan;
use App\Models\Subscription;
use App\Models\User;
use App\Models\Voucher;
use App\Services\Platform\SubscriptionAdmin;
use App\Support\Erp\BusinessTemplates;
use App\Support\PlatformSettings;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * The platform at a glance, for the operator's overview: revenue, growth,
 * the state of every company, people, voucher volume and module adoption.
 *
 * Every figure is an aggregate of real rows. Monthly series cover the last
 * twelve calendar months, oldest first, with empty months as zero so a chart
 * never skips one. Money is in the platform's default currency, the one
 * plans are sold in.
 */
class AnalyticsController extends Controller
{
    private const MONTHS = 12;

    public function __invoke()
    {
        $months = $this->months();
        $from = Carbon::parse($months->first().'-01')->startOfMonth();

        $paid = Invoice::query()->withoutGlobalScopes()
            ->where('status', 'paid')
            ->whereNotNull('paid_at')
            ->get(['id', 'company_id', 'total', 'paid_at', 'period_start', 'period_end']);

        $companies = Company::query()->with('plan:id,name')->withCount(['users'])->get();
        $vouchers = Voucher::query()->withoutGlobalScopes();

        $revenue = $this->series($months, $paid->filter(fn ($i) => $i->paid_at->gte($from)),
            fn ($i) => $i->paid_at->format('Y-m'), fn ($i) => (float) $i->total);

        $mrrSeries = $this->recognised($months, $paid);
        $thisMonth = $months->last();
        $lastMonth = $months->get(self::MONTHS - 2);

        $running = Subscription::query()->withoutGlobalScopes()
            ->with(['plan:id,name', 'company:id,name,status'])
            ->whereIn('status', ['active', 'past_due'])
            ->get();
        $mrr = round($running->sum(fn (Subscription $s) => $s->billing_cycle === 'annual' ? (float) $s->amount / 12 : (float) $s->amount), 2);

        $byStatus = $this->companiesByStatus($companies);

        return response()->json(['data' => [
            'currency' => PlatformSettings::currency(),
            'months' => $months->values(),
            'kpis' => [
                'mrr' => $mrr,
                'arr' => round($mrr * 12, 2),
                'revenue_this_month' => $revenue[$thisMonth],
                'revenue_last_month' => $revenue[$lastMonth],
                'revenue_12m' => round(array_sum($revenue), 2),
                'companies' => $companies->count(),
                'paying_companies' => $running->pluck('company_id')->unique()->count(),
                'trial_companies' => $byStatus['trial'],
                'pending_approvals' => $byStatus['pending'],
                'users' => User::whereNotNull('company_id')->count(),
                'active_users' => User::whereNotNull('company_id')->where('status', 'active')->count(),
                'active_users_30d' => User::whereNotNull('company_id')->where('last_login_at', '>=', now()->subDays(30))->count(),
                'vouchers' => (clone $vouchers)->count(),
                'vouchers_value' => round((float) (clone $vouchers)->sum('amount'), 2),
                'vouchers_this_month' => (clone $vouchers)->where('created_at', '>=', now()->startOfMonth())->count(),
            ],
            'revenue_by_month' => $this->points($months, $revenue),
            'mrr_by_month' => $this->points($months, $mrrSeries),
            'signups_by_month' => $this->points($months, $this->series(
                $months, $companies->filter(fn ($c) => $c->created_at?->gte($from)),
                fn ($c) => $c->created_at->format('Y-m'), fn () => 1,
            )),
            'vouchers_by_month' => $this->voucherMonths($months, $from),
            'companies_by_status' => $byStatus,
            'companies_by_plan' => $this->companiesByPlan($companies),
            'users_by_role' => User::query()->whereNotNull('company_id')
                ->selectRaw('role, count(*) as total')->groupBy('role')->orderByDesc('total')
                ->pluck('total', 'role')->map(fn ($n) => (int) $n),
            'module_adoption' => $this->moduleAdoption($companies),
            'churn' => $this->churn($companies),
            'expiring' => $this->expiring(),
            'pending' => $companies->where('status', Company::STATUS_PENDING)->sortBy('created_at')->take(8)
                ->map(fn (Company $c) => $this->companyRow($c))->values(),
            'recent_signups' => $companies->sortByDesc('id')->take(6)
                ->map(fn (Company $c) => $this->companyRow($c))->values(),
            'top_companies' => $this->topCompanies(),
        ]]);
    }

    /** @return Collection<int, string> 'Y-m' for the last twelve months, oldest first. */
    private function months(): Collection
    {
        return collect(range(self::MONTHS - 1, 0))
            ->map(fn (int $back) => now()->startOfMonth()->subMonthsNoOverflow($back)->format('Y-m'))
            ->values();
    }

    /** @return array<string, float> */
    private function series(Collection $months, Collection $rows, callable $month, callable $value): array
    {
        $out = $months->mapWithKeys(fn ($m) => [$m => 0.0])->all();

        foreach ($rows as $row) {
            $key = $month($row);
            if (array_key_exists($key, $out)) {
                $out[$key] += $value($row);
            }
        }

        return array_map(fn ($v) => round($v, 2), $out);
    }

    /**
     * Recognised monthly revenue: each paid invoice spread over the days of
     * the period it pays for, so a year's invoice adds a twelfth to each of
     * its months and a monthly one that starts mid-month is shared between
     * the two months it covers. That is what MRR means looking back.
     *
     * @return array<string, float>
     */
    private function recognised(Collection $months, Collection $paid): array
    {
        $out = $months->mapWithKeys(fn ($m) => [$m => 0.0])->all();

        foreach ($paid as $invoice) {
            $start = ($invoice->period_start ?? $invoice->paid_at)->copy()->startOfDay();
            $end = $invoice->period_end?->copy()->startOfDay();

            // Without a period it counts in full in the month it was paid.
            if (! $end || $end->lte($start)) {
                $key = $invoice->paid_at->format('Y-m');
                if (array_key_exists($key, $out)) {
                    $out[$key] += (float) $invoice->total;
                }

                continue;
            }

            $days = $start->diffInDays($end);

            foreach (array_keys($out) as $key) {
                $monthStart = Carbon::parse($key.'-01')->startOfDay();
                $monthEnd = $monthStart->copy()->addMonthNoOverflow();
                $from = $start->max($monthStart);
                $to = $end->min($monthEnd);

                if ($to->gt($from)) {
                    $out[$key] += (float) $invoice->total * $from->diffInDays($to) / $days;
                }
            }
        }

        return array_map(fn ($v) => round($v, 2), $out);
    }

    /** @param  array<string, float|int>  $series */
    private function points(Collection $months, array $series): array
    {
        return $months->map(fn ($m) => ['month' => $m, 'value' => $series[$m] ?? 0])->values()->all();
    }

    private function voucherMonths(Collection $months, Carbon $from): array
    {
        $created = Voucher::query()->withoutGlobalScopes()->where('created_at', '>=', $from)
            ->get(['created_at', 'amount']);
        $paid = Voucher::query()->withoutGlobalScopes()->whereNotNull('paid_at')->where('paid_at', '>=', $from)
            ->get(['paid_at', 'amount']);

        $count = $this->series($months, $created, fn ($v) => $v->created_at->format('Y-m'), fn () => 1);
        $value = $this->series($months, $created, fn ($v) => $v->created_at->format('Y-m'), fn ($v) => (float) $v->amount);
        $paidCount = $this->series($months, $paid, fn ($v) => $v->paid_at->format('Y-m'), fn () => 1);
        $paidValue = $this->series($months, $paid, fn ($v) => $v->paid_at->format('Y-m'), fn ($v) => (float) $v->amount);

        return $months->map(fn ($m) => [
            'month' => $m,
            'created' => (int) $count[$m],
            'created_value' => $value[$m],
            'paid' => (int) $paidCount[$m],
            'paid_value' => $paidValue[$m],
        ])->values()->all();
    }

    /** A company whose trial or paid period has run out reads as expired, whatever its stored status. */
    public static function effectiveStatus(Company $company): string
    {
        if (in_array($company->status, ['trial', 'active', 'past_due'], true) && $company->isExpired()) {
            return 'expired';
        }

        return $company->status;
    }

    /** @return array<string, int> */
    private function companiesByStatus(Collection $companies): array
    {
        $out = ['pending' => 0, 'trial' => 0, 'active' => 0, 'past_due' => 0, 'suspended' => 0, 'expired' => 0, 'cancelled' => 0];

        foreach ($companies as $company) {
            $status = self::effectiveStatus($company);
            $out[$status] = ($out[$status] ?? 0) + 1;
        }

        return $out;
    }

    private function companiesByPlan(Collection $companies): array
    {
        $rows = Plan::orderBy('sort_order')->orderBy('id')->get(['id', 'name'])
            ->map(fn (Plan $p) => ['plan_id' => $p->id, 'name' => $p->name, 'count' => $companies->where('plan_id', $p->id)->count()])
            ->filter(fn ($r) => $r['count'] > 0)
            ->values();

        $none = $companies->whereNull('plan_id')->count();
        if ($none > 0) {
            $rows->push(['plan_id' => null, 'name' => 'No plan', 'count' => $none]);
        }

        return $rows->all();
    }

    private function moduleAdoption(Collection $companies): array
    {
        $total = max(1, $companies->count());

        return collect(BusinessTemplates::modules())
            ->map(function (array $module, string $key) use ($companies, $total) {
                $count = $key === 'vouchflow'
                    ? $companies->count()
                    : $companies->filter(fn (Company $c) => in_array($key, (array) ($c->modules ?? []), true))->count();

                return [
                    'key' => $key,
                    'label' => $module['label'],
                    'live' => (bool) $module['live'],
                    'count' => $count,
                    'percent' => (int) round($count / $total * 100),
                ];
            })
            ->sortByDesc('count')
            ->values()
            ->all();
    }

    /**
     * Companies lost in the last 30 days: suspended or cancelled in that time,
     * or whose trial or paid period ran out in it without renewal. The rate
     * is against the companies that were live (not pending) at the time.
     */
    private function churn(Collection $companies): array
    {
        $since = now()->subDays(30);

        $lost = $companies->filter(function (Company $c) use ($since) {
            $status = self::effectiveStatus($c);

            if (in_array($status, ['suspended', 'cancelled'], true)) {
                return $c->updated_at && $c->updated_at->gte($since);
            }

            if ($status === 'expired') {
                $end = $c->status === 'trial' ? $c->trial_ends_at : $c->current_period_end;

                return $end && $end->gte($since);
            }

            return false;
        });

        $base = $companies->where('status', '!=', Company::STATUS_PENDING)->count();

        return [
            'period_days' => 30,
            'count' => $lost->count(),
            'rate' => $base ? round($lost->count() / $base * 100, 1) : 0.0,
            'suspended' => $lost->filter(fn ($c) => self::effectiveStatus($c) === 'suspended')->count(),
            'expired' => $lost->filter(fn ($c) => self::effectiveStatus($c) === 'expired')->count(),
            'cancelled' => $lost->filter(fn ($c) => self::effectiveStatus($c) === 'cancelled')->count(),
        ];
    }

    private function expiring(): array
    {
        return Subscription::query()->withoutGlobalScopes()
            ->with(['plan:id,name', 'company:id,name,status,email'])
            ->whereIn('status', SubscriptionAdmin::RUNNING)
            ->whereBetween('current_period_end', [now(), now()->addDays(30)])
            ->orderBy('current_period_end')
            ->limit(10)
            ->get()
            ->map(fn (Subscription $s) => [
                'id' => $s->id,
                'company_id' => $s->company_id,
                'company' => $s->company?->name,
                'plan' => $s->plan?->name,
                'status' => $s->status,
                'amount' => (float) $s->amount,
                'currency' => $s->currency,
                'cancel_at_period_end' => (bool) $s->cancel_at_period_end,
                'ends_at' => $s->current_period_end?->toIso8601String(),
                'days_left' => (int) max(0, now()->diffInDays($s->current_period_end, false)),
            ])
            ->all();
    }

    private function topCompanies(): array
    {
        $rows = Voucher::query()->withoutGlobalScopes()
            ->selectRaw('company_id, count(*) as vouchers, sum(amount) as value')
            ->groupBy('company_id')
            ->orderByDesc('vouchers')
            ->limit(6)
            ->get();

        $names = Company::query()->withTrashed()->whereIn('id', $rows->pluck('company_id'))->with('plan:id,name')->get()->keyBy('id');

        return $rows->map(fn ($r) => [
            'id' => (int) $r->company_id,
            'name' => $names->get($r->company_id)?->name ?? 'Deleted company',
            'plan' => $names->get($r->company_id)?->plan?->name,
            'currency' => $names->get($r->company_id)?->currency ?? PlatformSettings::currency(),
            'vouchers' => (int) $r->vouchers,
            'value' => round((float) $r->value, 2),
        ])->all();
    }

    private function companyRow(Company $c): array
    {
        return [
            'id' => $c->id,
            'name' => $c->name,
            'email' => $c->email,
            'plan' => $c->plan?->name,
            'status' => self::effectiveStatus($c),
            'users_count' => (int) $c->users_count,
            'created_at' => $c->created_at?->toIso8601String(),
        ];
    }
}
