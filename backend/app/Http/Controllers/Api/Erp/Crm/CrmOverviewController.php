<?php

namespace App\Http\Controllers\Api\Erp\Crm;

use App\Http\Controllers\Controller;
use App\Models\Erp\Crm\Activity;
use App\Models\Erp\Crm\Lead;
use App\Models\Erp\Crm\Opportunity;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * The CRM's figures: the pipeline by stage, what was won this month, the
 * follow-ups due, the weighted forecast and why deals close. Everything is
 * limited to what the caller may see, so a salesperson's overview is theirs.
 */
class CrmOverviewController extends Controller
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function overview(Request $request): JsonResponse
    {
        $user = $request->user();
        $deals = Opportunity::query()->visibleTo($user);
        $monthStart = now()->startOfMonth();

        $stages = (clone $deals)->selectRaw('stage, count(*) as count, coalesce(sum(value), 0) as value, coalesce(sum(value * probability / 100), 0) as weighted')
            ->groupBy('stage')->get()->keyBy('stage');

        $won = (clone $deals)->where('stage', Opportunity::STAGE_WON)->where('closed_at', '>=', $monthStart);
        $lost = (clone $deals)->where('stage', Opportunity::STAGE_LOST)->where('closed_at', '>=', $monthStart);

        $activities = fn () => Activity::query()->visibleTo($user)->whereNull('completed_at')
            ->with(['owner:id,name', 'lead:id,number,contact_name', 'opportunity:id,number,title', 'customer:id,code,name']);

        $leads = Lead::query()->visibleTo($user)->selectRaw('status, count(*) as count')->groupBy('status')->pluck('count', 'status');

        return response()->json(['data' => [
            'stages' => array_map(fn ($stage) => [
                'stage' => $stage,
                'count' => (int) ($stages[$stage]->count ?? 0),
                'value' => round((float) ($stages[$stage]->value ?? 0), 2),
                'weighted' => round((float) ($stages[$stage]->weighted ?? 0), 2),
            ], Opportunity::STAGES),
            'open_value' => round((float) collect(Opportunity::OPEN_STAGES)->sum(fn ($s) => $stages[$s]->value ?? 0), 2),
            'weighted_value' => round((float) collect(Opportunity::OPEN_STAGES)->sum(fn ($s) => $stages[$s]->weighted ?? 0), 2),
            'won_this_month' => ['count' => (clone $won)->count(), 'value' => round((float) (clone $won)->sum('value'), 2)],
            'lost_this_month' => ['count' => (clone $lost)->count(), 'value' => round((float) (clone $lost)->sum('value'), 2)],
            'leads' => collect([...Lead::STATUSES, Lead::STATUS_CONVERTED])->mapWithKeys(fn ($s) => [$s => (int) ($leads[$s] ?? 0)]),
            'due_today' => $activities()->whereDate('due_at', today())->orderBy('due_at')->limit(20)->get(),
            'overdue' => $activities()->where('due_at', '<', today())->orderBy('due_at')->limit(20)->get(),
            'overdue_count' => $activities()->where('due_at', '<', today())->count(),
            'due_today_count' => $activities()->whereDate('due_at', today())->count(),
        ]]);
    }

    /**
     * Open deals by the month they are expected to close, at full and at
     * weighted value (value x probability), with deals whose date has passed
     * shown on their own, and what was actually won in each month beside it.
     */
    public function forecast(Request $request): JsonResponse
    {
        $user = $request->user();
        $months = max(1, min((int) $request->query('months', 6), 12));
        $start = now()->startOfMonth();

        $open = Opportunity::query()->visibleTo($user)->whereIn('stage', Opportunity::OPEN_STAGES)
            ->get(['id', 'value', 'probability', 'expected_close_date', 'stage']);
        $won = Opportunity::query()->visibleTo($user)->where('stage', Opportunity::STAGE_WON)
            ->where('closed_at', '>=', $start)->get(['id', 'value', 'closed_at']);

        $rows = [];
        for ($i = 0; $i < $months; $i++) {
            $month = $start->copy()->addMonths($i);
            $key = $month->format('Y-m');
            $deals = $open->filter(fn ($o) => $o->expected_close_date?->format('Y-m') === $key);
            $rows[] = [
                'month' => $key,
                'count' => $deals->count(),
                'value' => round((float) $deals->sum('value'), 2),
                'weighted' => round((float) $deals->sum(fn ($o) => $o->value * $o->probability / 100), 2),
                'won' => round((float) $won->filter(fn ($o) => $o->closed_at->format('Y-m') === $key)->sum('value'), 2),
            ];
        }

        $late = $open->filter(fn ($o) => $o->expected_close_date && $o->expected_close_date->lt($start));
        $undated = $open->filter(fn ($o) => ! $o->expected_close_date);
        $beyond = $open->filter(fn ($o) => $o->expected_close_date && $o->expected_close_date->gte($start->copy()->addMonths($months)));

        $bucket = fn ($deals) => [
            'count' => $deals->count(),
            'value' => round((float) $deals->sum('value'), 2),
            'weighted' => round((float) $deals->sum(fn ($o) => $o->value * $o->probability / 100), 2),
        ];

        return response()->json(['data' => [
            'months' => $rows,
            'past_due' => $bucket($late),
            'later' => $bucket($beyond),
            'undated' => $bucket($undated),
            'total' => $bucket($open),
        ]]);
    }

    /** Closed deals by the reason recorded, over the last twelve months. */
    public function winLoss(Request $request): JsonResponse
    {
        $since = Carbon::now()->subMonths(12);
        $closed = Opportunity::query()->visibleTo($request->user())
            ->whereIn('stage', [Opportunity::STAGE_WON, Opportunity::STAGE_LOST])
            ->where('closed_at', '>=', $since)
            ->get(['id', 'stage', 'close_reason', 'value']);

        $summarise = fn (string $stage) => $closed->where('stage', $stage)->groupBy(fn ($o) => $o->close_reason ?: 'unspecified')
            ->map(fn ($group, $reason) => ['reason' => $reason, 'count' => $group->count(), 'value' => round((float) $group->sum('value'), 2)])
            ->sortByDesc('count')->values();

        $wonCount = $closed->where('stage', Opportunity::STAGE_WON)->count();

        return response()->json(['data' => [
            'won' => $summarise(Opportunity::STAGE_WON),
            'lost' => $summarise(Opportunity::STAGE_LOST),
            'win_rate' => $closed->count() ? round($wonCount / $closed->count() * 100, 1) : null,
            'reasons' => ['won' => Opportunity::WIN_REASONS, 'lost' => Opportunity::LOSS_REASONS],
        ]]);
    }

    /** People CRM records can be assigned to: everyone active in the company. */
    public function people(): JsonResponse
    {
        return response()->json(['data' => User::query()
            ->where('company_id', $this->tenant->id())
            ->where('status', 'active')
            ->orderBy('name')
            ->get(['id', 'name', 'role'])]);
    }
}
