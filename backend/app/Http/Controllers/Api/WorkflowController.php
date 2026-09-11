<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\WorkflowResource;
use App\Models\Workflow;
use App\Models\WorkflowStep;
use App\Services\AuditLogger;
use App\Services\CompanyProvisioner;
use App\Services\UsageLimits;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * The workflow builder. A company defines its own steps, their order, who acts at
 * each and exactly what that step may do — sign, approve, reject, request changes,
 * print, download. Two tenants can run entirely different routes.
 */
class WorkflowController extends Controller
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly UsageLimits $limits,
        private readonly CompanyProvisioner $provisioner,
        private readonly TenantContext $tenant,
    ) {}

    public function index()
    {
        return WorkflowResource::collection(
            Workflow::with(['steps.assignedUser', 'voucherType'])
                ->orderByDesc('is_default')
                ->orderBy('name')
                ->get()
        );
    }

    public function show(Workflow $workflow)
    {
        return new WorkflowResource($workflow->load(['steps.assignedUser', 'voucherType']));
    }

    public function store(Request $request)
    {
        $this->authorizeAdmin($request);

        $data = $this->validateWorkflow($request);
        $this->limits->assertApprovalDepth($this->tenant->company(), $data['steps']);

        $workflow = DB::transaction(function () use ($data) {
            if ($data['is_default'] ?? false) {
                Workflow::where('is_default', true)->update(['is_default' => false]);
            }

            $workflow = Workflow::create([
                'name' => $data['name'],
                'description' => $data['description'] ?? null,
                'voucher_type_id' => $data['voucher_type_id'] ?? null,
                'is_default' => $data['is_default'] ?? false,
                'is_active' => $data['is_active'] ?? true,
                'created_by' => auth()->id(),
            ]);

            $this->syncSteps($workflow, $data['steps']);

            return $workflow;
        });

        $this->audit->log('workflow.created', "Created workflow {$workflow->name}", $workflow);

        return (new WorkflowResource($workflow->load('steps.assignedUser')))->response()->setStatusCode(201);
    }

    public function update(Request $request, Workflow $workflow)
    {
        $this->authorizeAdmin($request);

        $data = $this->validateWorkflow($request);
        $this->limits->assertApprovalDepth($this->tenant->company(), $data['steps']);

        $before = ['route' => $workflow->load('steps')->routeSummary(), 'version' => $workflow->version];

        DB::transaction(function () use ($workflow, $data) {
            if ($data['is_default'] ?? false) {
                Workflow::where('is_default', true)->where('id', '!=', $workflow->id)->update(['is_default' => false]);
            }

            $workflow->update([
                'name' => $data['name'],
                'description' => $data['description'] ?? null,
                'voucher_type_id' => $data['voucher_type_id'] ?? null,
                'is_default' => $data['is_default'] ?? $workflow->is_default,
                'is_active' => $data['is_active'] ?? $workflow->is_active,
                'version' => $workflow->version + 1,
            ]);

            $this->syncSteps($workflow, $data['steps']);
        });

        $workflow->refresh()->load('steps.assignedUser');

        $this->audit->log(
            'workflow.updated',
            "Changed approval workflow {$workflow->name}",
            $workflow,
            $before,
            ['route' => $workflow->routeSummary(), 'version' => $workflow->version],
        );

        return new WorkflowResource($workflow);
    }

    public function destroy(Request $request, Workflow $workflow)
    {
        $this->authorizeAdmin($request);

        abort_if($workflow->is_default, 422, 'The default workflow cannot be deleted. Make another one default first.');
        abort_if($workflow->vouchers()->exists(), 422, 'Vouchers reference this workflow. Deactivate it instead of deleting it.');

        $name = $workflow->name;
        $workflow->delete();

        $this->audit->log('workflow.deleted', "Deleted workflow {$name}", $workflow);

        return response()->json(['message' => "Workflow {$name} deleted."]);
    }

    /** The presets offered in the builder. */
    public function presets()
    {
        return response()->json([
            'data' => collect(CompanyProvisioner::PRESETS)->map(fn ($preset, $key) => [
                'key' => $key,
                'name' => $preset['name'],
                'description' => $preset['description'],
                'steps' => count($preset['steps']),
            ])->values(),
        ]);
    }

    public function applyPreset(Request $request)
    {
        $this->authorizeAdmin($request);

        $data = $request->validate([
            'preset' => ['required', Rule::in(array_keys(CompanyProvisioner::PRESETS))],
        ]);

        $workflow = $this->provisioner->applyPreset($this->tenant->company(), $data['preset'], $request->user());

        $this->audit->log('workflow.preset_applied', "Applied the '{$workflow->name}' workflow preset", $workflow);

        return new WorkflowResource($workflow->load('steps.assignedUser'));
    }

    private function syncSteps(Workflow $workflow, array $steps): void
    {
        $keep = [];

        foreach (array_values($steps) as $index => $step) {
            $payload = [
                'workflow_id' => $workflow->id,
                'position' => $index + 1,
                'name' => $step['name'],
                'name_sw' => $step['name_sw'] ?? null,
                'role' => $step['role'],
                'assigned_user_id' => $step['assigned_user_id'] ?? null,
                'assignee_hint' => $step['assignee_hint'] ?? null,
                'can_sign' => $step['can_sign'] ?? false,
                'can_approve' => $step['can_approve'] ?? false,
                'can_reject' => $step['can_reject'] ?? false,
                'can_request_changes' => $step['can_request_changes'] ?? false,
                'can_print' => $step['can_print'] ?? true,
                'can_download' => $step['can_download'] ?? true,
                'can_pay' => $step['can_pay'] ?? false,
                'requires_signature' => $step['requires_signature'] ?? ($step['can_sign'] ?? false),
                'min_amount' => $step['min_amount'] ?? null,
                'max_amount' => $step['max_amount'] ?? null,
            ];

            // Positions are unique per workflow; clear the slot before reusing it.
            WorkflowStep::where('workflow_id', $workflow->id)
                ->where('position', $payload['position'])
                ->when(isset($step['id']), fn ($q) => $q->where('id', '!=', $step['id']))
                ->update(['position' => DB::raw('position + 1000')]);

            $model = isset($step['id'])
                ? WorkflowStep::where('workflow_id', $workflow->id)->find($step['id'])
                : null;

            if ($model) {
                $model->update($payload);
            } else {
                $model = WorkflowStep::create($payload);
            }

            $keep[] = $model->id;
        }

        WorkflowStep::where('workflow_id', $workflow->id)->whereNotIn('id', $keep)->delete();
    }

    private function validateWorkflow(Request $request): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'description' => ['nullable', 'string', 'max:255'],
            'voucher_type_id' => ['nullable', 'integer', Rule::exists('voucher_types', 'id')->where('company_id', $this->tenant->id())],
            'is_default' => ['nullable', 'boolean'],
            'is_active' => ['nullable', 'boolean'],

            'steps' => ['required', 'array', 'min:1', 'max:12'],
            'steps.*.id' => ['nullable', 'integer'],
            'steps.*.name' => ['required', 'string', 'max:120'],
            'steps.*.name_sw' => ['nullable', 'string', 'max:120'],
            'steps.*.role' => ['required', Rule::in(WorkflowStep::ROLES)],
            'steps.*.assigned_user_id' => ['nullable', 'integer', Rule::exists('users', 'id')->where('company_id', $this->tenant->id())],
            'steps.*.assignee_hint' => ['nullable', 'string', 'max:180'],
            'steps.*.can_sign' => ['nullable', 'boolean'],
            'steps.*.can_approve' => ['nullable', 'boolean'],
            'steps.*.can_reject' => ['nullable', 'boolean'],
            'steps.*.can_request_changes' => ['nullable', 'boolean'],
            'steps.*.can_print' => ['nullable', 'boolean'],
            'steps.*.can_download' => ['nullable', 'boolean'],
            'steps.*.can_pay' => ['nullable', 'boolean'],
            'steps.*.requires_signature' => ['nullable', 'boolean'],
            'steps.*.min_amount' => ['nullable', 'numeric', 'min:0'],
            'steps.*.max_amount' => ['nullable', 'numeric', 'min:0'],
        ]);
    }

    private function authorizeAdmin(Request $request): void
    {
        abort_unless($request->user()->isAdmin(), 403, 'Only an administrator may change the approval workflow.');
    }
}
