<?php

namespace App\Http\Controllers\Api\Erp\Crm;

use App\Http\Controllers\Controller;
use App\Models\Erp\Crm\Activity;
use App\Models\Erp\Crm\Lead;
use App\Models\Erp\Crm\Opportunity;
use App\Services\AuditLogger;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * Calls, meetings, visits and tasks. An activity linked to a lead or an
 * opportunity may only be added by someone who can see that record.
 */
class ActivityController extends Controller
{
    use AssignsOwner;

    public function __construct(
        private readonly TenantContext $tenant,
        private readonly AuditLogger $audit,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $today = today();

        return response()->json(Activity::query()
            ->visibleTo($request->user())
            ->with(['owner:id,name', 'lead:id,number,contact_name', 'opportunity:id,number,title', 'customer:id,code,name'])
            ->when($request->query('type'), fn ($q, $v) => $q->where('type', $v))
            ->when($request->query('lead_id'), fn ($q, $v) => $q->where('lead_id', $v))
            ->when($request->query('opportunity_id'), fn ($q, $v) => $q->where('opportunity_id', $v))
            ->when($request->query('customer_id'), fn ($q, $v) => $q->where('customer_id', $v))
            ->when($request->query('owner_id'), fn ($q, $v) => $q->where('owner_id', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where('subject', 'like', "%{$v}%"))
            ->when($request->query('status'), fn ($q, $v) => match ($v) {
                'open' => $q->whereNull('completed_at'),
                'done' => $q->whereNotNull('completed_at'),
                'today' => $q->whereNull('completed_at')->whereDate('due_at', $today),
                'overdue' => $q->whereNull('completed_at')->where('due_at', '<', $today),
                default => $q,
            })
            ->orderByRaw('completed_at is not null')
            ->orderBy('due_at')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->rules($request);
        $this->assertLinksVisible($request, $data);
        $data['owner_id'] = $this->ownerFor($request, $data['owner_id'] ?? null);

        $activity = Activity::create([...$data, 'created_by' => $request->user()->id]);
        $this->audit->log('crm.activity_created', "Scheduled {$activity->type}: {$activity->subject}", $activity);

        return response()->json(['data' => $activity->load('owner:id,name')], 201);
    }

    public function update(Request $request, Activity $activity): JsonResponse
    {
        $this->authorizeActivity($request, $activity);
        $data = $this->rules($request, true);
        $this->assertLinksVisible($request, $data);

        if (array_key_exists('owner_id', $data)) {
            $data['owner_id'] = $this->ownerFor($request, $data['owner_id'], $activity->owner_id);
        }

        $before = $activity->only(array_keys($data));
        $activity->update($data);
        $this->audit->log('crm.activity_updated', "Updated {$activity->type}: {$activity->subject}", $activity, $before, $activity->only(array_keys($data)));

        return response()->json(['data' => $activity->load('owner:id,name')]);
    }

    public function complete(Request $request, Activity $activity): JsonResponse
    {
        $this->authorizeActivity($request, $activity);
        $outcome = $request->validate(['outcome' => ['nullable', 'string', 'max:255']])['outcome'] ?? null;

        if ($activity->completed_at) {
            throw new RuntimeException('This activity is already done.');
        }

        $activity->update(['completed_at' => now(), 'completed_by' => $request->user()->id, 'outcome' => $outcome]);
        $this->audit->log('crm.activity_completed', "Completed {$activity->type}: {$activity->subject}", $activity);

        return response()->json(['data' => $activity]);
    }

    public function reopen(Request $request, Activity $activity): JsonResponse
    {
        $this->authorizeActivity($request, $activity);
        $activity->update(['completed_at' => null, 'completed_by' => null]);
        $this->audit->log('crm.activity_reopened', "Reopened {$activity->type}: {$activity->subject}", $activity);

        return response()->json(['data' => $activity]);
    }

    public function destroy(Request $request, Activity $activity): JsonResponse
    {
        $this->authorizeActivity($request, $activity);
        $activity->delete();
        $this->audit->log('crm.activity_deleted', "Removed {$activity->type}: {$activity->subject}", $activity);

        return response()->json(['message' => 'Activity removed.']);
    }

    private function authorizeActivity(Request $request, Activity $activity): void
    {
        abort_unless($activity->isVisibleTo($request->user()), 404);
    }

    private function assertLinksVisible(Request $request, array $data): void
    {
        $user = $request->user();

        if (! empty($data['lead_id']) && ! Lead::query()->findOrFail($data['lead_id'])->isVisibleTo($user)) {
            abort(404);
        }

        if (! empty($data['opportunity_id']) && ! Opportunity::query()->findOrFail($data['opportunity_id'])->isVisibleTo($user)) {
            abort(404);
        }
    }

    private function rules(Request $request, bool $partial = false): array
    {
        $required = $partial ? 'sometimes' : 'required';
        $company = $this->tenant->id();

        return $request->validate([
            'type' => [$required, Rule::in(Activity::TYPES)],
            'subject' => [$required, 'string', 'max:180'],
            'notes' => ['nullable', 'string', 'max:5000'],
            'due_at' => ['nullable', 'date'],
            'lead_id' => ['nullable', 'integer', Rule::exists('crm_leads', 'id')->where('company_id', $company)],
            'opportunity_id' => ['nullable', 'integer', Rule::exists('crm_opportunities', 'id')->where('company_id', $company)],
            'customer_id' => ['nullable', 'integer', Rule::exists('customers', 'id')->where('company_id', $company)],
            'owner_id' => ['sometimes', 'nullable', 'integer', Rule::exists('users', 'id')->where('company_id', $company)],
        ]);
    }
}
