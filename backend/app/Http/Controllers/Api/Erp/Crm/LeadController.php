<?php

namespace App\Http\Controllers\Api\Erp\Crm;

use App\Http\Controllers\Controller;
use App\Models\Erp\Crm\Lead;
use App\Models\Erp\Crm\Opportunity;
use App\Services\AuditLogger;
use App\Services\Erp\Crm\Pipeline;
use App\Services\Erp\DocumentNumberer;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Exists;
use RuntimeException;

/**
 * Leads: people and businesses who might buy. A salesperson sees and works
 * the ones they own; crm.view_all sees everyone's.
 */
class LeadController extends Controller
{
    use AssignsOwner;

    public function __construct(
        private readonly TenantContext $tenant,
        private readonly AuditLogger $audit,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json(Lead::query()
            ->visibleTo($user)
            ->with(['owner:id,name', 'customer:id,code,name'])
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('source'), fn ($q, $v) => $q->where('source', $v))
            ->when($request->query('region'), fn ($q, $v) => $q->where('region', $v))
            ->when($request->query('owner_id'), fn ($q, $v) => $q->where('owner_id', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                ->where('contact_name', 'like', "%{$v}%")->orWhere('company_name', 'like', "%{$v}%")
                ->orWhere('number', 'like', "%{$v}%")->orWhere('phone', 'like', "%{$v}%")->orWhere('email', 'like', "%{$v}%")))
            ->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function regions(Request $request): JsonResponse
    {
        return response()->json(['data' => Lead::query()->visibleTo($request->user())
            ->whereNotNull('region')->distinct()->orderBy('region')->pluck('region')]);
    }

    public function show(Request $request, Lead $lead): JsonResponse
    {
        $this->authorizeLead($request, $lead);

        return response()->json(['data' => $lead->load([
            'owner:id,name', 'customer:id,code,name', 'opportunity:id,number,title,stage,value',
            'activities' => fn ($q) => $q->with('owner:id,name')->orderByRaw('completed_at is not null')->orderBy('due_at'),
        ])]);
    }

    public function store(Request $request, DocumentNumberer $numbers): JsonResponse
    {
        $data = $this->rules($request);
        $data['owner_id'] = $this->ownerFor($request, $data['owner_id'] ?? null);

        $lead = Lead::create([...$data, 'number' => $numbers->next('LEAD'), 'status' => $data['status'] ?? Lead::STATUS_NEW, 'created_by' => $request->user()->id]);
        $this->audit->log('crm.lead_created', "Added lead {$lead->number}, {$lead->contact_name}", $lead);

        return response()->json(['data' => $lead->load('owner:id,name')], 201);
    }

    public function update(Request $request, Lead $lead): JsonResponse
    {
        $this->authorizeLead($request, $lead);

        if ($lead->isConverted()) {
            throw new RuntimeException("{$lead->number} has been converted; work on its opportunity instead.");
        }

        $data = $this->rules($request, true);

        if (array_key_exists('owner_id', $data)) {
            $data['owner_id'] = $this->ownerFor($request, $data['owner_id'], $lead->owner_id);
        }

        if (($data['status'] ?? null) === Lead::STATUS_LOST && empty($data['lost_reason']) && ! $lead->lost_reason) {
            throw new RuntimeException('Say why the lead was lost.');
        }

        $before = $lead->only(array_keys($data));
        $lead->update($data);
        $this->audit->log('crm.lead_updated', "Updated lead {$lead->number}", $lead, $before, $lead->only(array_keys($data)));

        return response()->json(['data' => $lead->load('owner:id,name')]);
    }

    public function assign(Request $request, Lead $lead): JsonResponse
    {
        $this->authorizeLead($request, $lead);
        $owner = $request->validate(['owner_id' => ['required', 'integer', $this->companyUser()]])['owner_id'];

        $before = ['owner_id' => $lead->owner_id];
        $lead->update(['owner_id' => $owner]);
        $this->audit->log('crm.lead_assigned', "Assigned lead {$lead->number}", $lead, $before, ['owner_id' => $owner]);

        return response()->json(['data' => $lead->load('owner:id,name')]);
    }

    public function convert(Request $request, Lead $lead, Pipeline $pipeline): JsonResponse
    {
        $this->authorizeLead($request, $lead);

        $options = $request->validate([
            'customer_id' => ['nullable', 'integer', Rule::exists('customers', 'id')->where('company_id', $this->tenant->id())->whereNull('deleted_at')],
            'title' => ['nullable', 'string', 'max:180'],
            'value' => ['nullable', 'numeric', 'min:0'],
            'expected_close_date' => ['nullable', 'date'],
            'stage' => ['nullable', Rule::in(Opportunity::OPEN_STAGES)],
        ]);

        $result = $pipeline->convert($lead, $options, $request->user());

        return response()->json([
            'message' => "{$result['lead']->number} converted.",
            'data' => ['lead' => $result['lead'], 'customer' => $result['customer'], 'opportunity' => $result['opportunity']],
        ]);
    }

    private function authorizeLead(Request $request, Lead $lead): void
    {
        // Someone else's lead is as invisible as another company's.
        abort_unless($lead->isVisibleTo($request->user()), 404);
    }

    private function companyUser(): Exists
    {
        return Rule::exists('users', 'id')->where('company_id', $this->tenant->id());
    }

    private function rules(Request $request, bool $partial = false): array
    {
        $required = $partial ? 'sometimes' : 'required';

        return $request->validate([
            'contact_name' => [$required, 'string', 'max:150'],
            'company_name' => ['nullable', 'string', 'max:180'],
            'phone' => ['nullable', 'string', 'max:40'],
            'email' => ['nullable', 'email', 'max:180'],
            'region' => ['nullable', 'string', 'max:80'],
            'source' => [$required, Rule::in(Lead::SOURCES)],
            'status' => ['sometimes', Rule::in(Lead::STATUSES)],
            'estimated_value' => ['sometimes', 'numeric', 'min:0', 'max:9999999999999'],
            'notes' => ['nullable', 'string', 'max:5000'],
            'lost_reason' => ['nullable', 'string', 'max:255'],
            'owner_id' => ['sometimes', 'nullable', 'integer', $this->companyUser()],
        ]);
    }
}
