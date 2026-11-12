<?php

namespace App\Http\Controllers\Api\Erp\Crm;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Erp\Crm\Opportunity;
use App\Services\AuditLogger;
use App\Services\Erp\Crm\Pipeline;
use App\Services\Erp\DocumentNumberer;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * Opportunities and the pipeline board. Stage changes go through Pipeline,
 * which locks the deal and writes the audit entry the board's history reads.
 */
class OpportunityController extends Controller
{
    use AssignsOwner;

    public function __construct(
        private readonly TenantContext $tenant,
        private readonly AuditLogger $audit,
    ) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json($this->query($request)
            ->when($request->query('stage'), fn ($q, $v) => $q->where('stage', $v))
            ->when($request->boolean('open_only'), fn ($q) => $q->whereIn('stage', Opportunity::OPEN_STAGES))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    /** Every deal grouped by stage, for the Kanban board. Closed deals show the last 90 days. */
    public function board(Request $request): JsonResponse
    {
        $rows = $this->query($request)
            ->where(fn ($q) => $q->whereIn('stage', Opportunity::OPEN_STAGES)->orWhere('closed_at', '>=', now()->subDays(90)))
            ->orderBy('expected_close_date')
            ->limit(500)
            ->get();

        $columns = [];
        foreach (Opportunity::STAGES as $stage) {
            $items = $rows->where('stage', $stage)->values();
            $columns[] = [
                'stage' => $stage,
                'count' => $items->count(),
                'value' => round((float) $items->sum('value'), 2),
                'weighted' => round((float) $items->sum(fn ($o) => $o->value * $o->probability / 100), 2),
                'items' => $items,
            ];
        }

        return response()->json(['data' => $columns]);
    }

    public function show(Request $request, Opportunity $opportunity): JsonResponse
    {
        $this->authorizeDeal($request, $opportunity);

        $history = AuditLog::query()
            ->where('company_id', $this->tenant->id())
            ->where('entity_type', class_basename($opportunity))
            ->where('entity_id', $opportunity->id)
            ->latest('id')->limit(50)
            ->get(['id', 'action', 'actor_name', 'description', 'change_summary', 'created_at']);

        return response()->json(['data' => [
            ...$opportunity->load([
                'owner:id,name', 'customer:id,code,name,phone,email', 'lead:id,number,contact_name',
                'activities' => fn ($q) => $q->with('owner:id,name')->orderByRaw('completed_at is not null')->orderBy('due_at'),
            ])->toArray(),
            'history' => $history,
        ]]);
    }

    public function store(Request $request, DocumentNumberer $numbers): JsonResponse
    {
        $data = $this->rules($request);
        $data['owner_id'] = $this->ownerFor($request, $data['owner_id'] ?? null);
        $stage = $data['stage'] ?? Opportunity::STAGE_PROSPECTING;

        if (! in_array($stage, Opportunity::OPEN_STAGES, true)) {
            throw new RuntimeException('A new opportunity starts in an open stage; close it from the board.');
        }

        $opportunity = Opportunity::create([
            ...$data,
            'number' => $numbers->next('OPP'),
            'stage' => $stage,
            'probability' => $data['probability'] ?? Opportunity::DEFAULT_PROBABILITY[$stage],
            'stage_changed_at' => now(),
            'created_by' => $request->user()->id,
        ]);
        $this->audit->log('crm.opportunity_created', "Opened {$opportunity->number}, {$opportunity->title}", $opportunity);

        return response()->json(['data' => $opportunity->load('owner:id,name', 'customer:id,code,name')], 201);
    }

    public function update(Request $request, Opportunity $opportunity): JsonResponse
    {
        $this->authorizeDeal($request, $opportunity);
        $data = $this->rules($request, true);
        unset($data['stage']);

        if (array_key_exists('owner_id', $data)) {
            $data['owner_id'] = $this->ownerFor($request, $data['owner_id'], $opportunity->owner_id);
        }

        if (! $opportunity->isOpen() && array_key_exists('probability', $data)) {
            unset($data['probability']);
        }

        $before = $opportunity->only(array_keys($data));
        $opportunity->update($data);
        $this->audit->log('crm.opportunity_updated', "Updated {$opportunity->number}", $opportunity, $before, $opportunity->only(array_keys($data)));

        return response()->json(['data' => $opportunity->load('owner:id,name', 'customer:id,code,name')]);
    }

    public function stage(Request $request, Opportunity $opportunity, Pipeline $pipeline): JsonResponse
    {
        $this->authorizeDeal($request, $opportunity);

        $data = $request->validate([
            'stage' => ['required', Rule::in(Opportunity::STAGES)],
            'reason' => ['nullable', 'string', 'max:40'],
            'note' => ['nullable', 'string', 'max:255'],
        ]);

        $deal = $pipeline->moveStage($opportunity, $data['stage'], $data['reason'] ?? null, $data['note'] ?? null, $request->user());

        return response()->json(['message' => "{$deal->number} is now {$deal->stage}.", 'data' => $deal->load('owner:id,name', 'customer:id,code,name')]);
    }

    public function assign(Request $request, Opportunity $opportunity): JsonResponse
    {
        $this->authorizeDeal($request, $opportunity);
        $owner = $request->validate(['owner_id' => ['required', 'integer', Rule::exists('users', 'id')->where('company_id', $this->tenant->id())]])['owner_id'];

        $before = ['owner_id' => $opportunity->owner_id];
        $opportunity->update(['owner_id' => $owner]);
        $this->audit->log('crm.opportunity_assigned', "Assigned {$opportunity->number}", $opportunity, $before, ['owner_id' => $owner]);

        return response()->json(['data' => $opportunity->load('owner:id,name')]);
    }

    private function query(Request $request)
    {
        return Opportunity::query()
            ->visibleTo($request->user())
            ->with(['owner:id,name', 'customer:id,code,name'])
            ->when($request->query('owner_id'), fn ($q, $v) => $q->where('owner_id', $v))
            ->when($request->query('customer_id'), fn ($q, $v) => $q->where('customer_id', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                ->where('title', 'like', "%{$v}%")->orWhere('number', 'like', "%{$v}%")
                ->orWhereHas('customer', fn ($c) => $c->where('name', 'like', "%{$v}%"))));
    }

    private function authorizeDeal(Request $request, Opportunity $opportunity): void
    {
        abort_unless($opportunity->isVisibleTo($request->user()), 404);
    }

    private function rules(Request $request, bool $partial = false): array
    {
        $required = $partial ? 'sometimes' : 'required';

        return $request->validate([
            'title' => [$required, 'string', 'max:180'],
            'customer_id' => ['nullable', 'integer', Rule::exists('customers', 'id')->where('company_id', $this->tenant->id())->whereNull('deleted_at')],
            'stage' => ['sometimes', Rule::in(Opportunity::STAGES)],
            'value' => [$required, 'numeric', 'min:0', 'max:9999999999999'],
            'probability' => ['sometimes', 'integer', 'min:0', 'max:100'],
            'expected_close_date' => ['nullable', 'date'],
            'notes' => ['nullable', 'string', 'max:5000'],
            'owner_id' => ['sometimes', 'nullable', 'integer', Rule::exists('users', 'id')->where('company_id', $this->tenant->id())],
        ]);
    }
}
