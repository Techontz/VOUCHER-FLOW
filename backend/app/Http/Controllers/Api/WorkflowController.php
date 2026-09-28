<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\WorkflowResource;
use App\Models\Department;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherType;
use App\Models\Workflow;
use App\Models\WorkflowStep;
use App\Services\AuditLogger;
use App\Services\CompanyProvisioner;
use App\Services\UsageLimits;
use App\Services\WorkflowEngine;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * The workflow builder. A company defines its own steps, their order, who acts at
 * each and exactly what that step may do — sign, approve, reject, request changes,
 * print, download. Two tenants can run entirely different routes.
 */
class WorkflowController extends Controller
{
    /** Voucher statuses that are still moving through their workflow. */
    private const IN_FLIGHT = [
        Voucher::STATUS_DRAFT,
        Voucher::STATUS_IN_REVIEW,
        Voucher::STATUS_CHANGES_REQUESTED,
        Voucher::STATUS_APPROVED,
    ];

    public function __construct(
        private readonly AuditLogger $audit,
        private readonly UsageLimits $limits,
        private readonly CompanyProvisioner $provisioner,
        private readonly TenantContext $tenant,
        private readonly WorkflowEngine $engine,
    ) {}

    public function index()
    {
        return WorkflowResource::collection(
            $this->withUsage(Workflow::with(['steps.assignedUser', 'voucherType']))
                ->orderByDesc('is_default')
                ->orderBy('name')
                ->get()
        );
    }

    public function show(Workflow $workflow)
    {
        return new WorkflowResource($this->reload($workflow));
    }

    /**
     * Creates a workflow from an explicit list of steps, or from one of the
     * presets when `from_preset` is given without steps.
     */
    public function store(Request $request)
    {
        $this->authorizeAdmin($request);

        $data = $this->validateWorkflow($request, null);
        $this->limits->assertApprovalDepth($this->tenant->company(), $data['steps']);

        $workflow = DB::transaction(function () use ($data) {
            if ($data['is_default'] ?? false) {
                Workflow::where('is_default', true)->update(['is_default' => false]);
            }

            $workflow = Workflow::create([
                'name' => $data['name'],
                'name_sw' => $data['name_sw'] ?? null,
                'description' => $data['description'] ?? null,
                'voucher_type_id' => $data['voucher_type_id'] ?? null,
                'is_default' => $data['is_default'] ?? false,
                'is_active' => ($data['is_default'] ?? false) ? true : ($data['is_active'] ?? true),
                'created_by' => auth()->id(),
            ]);

            $this->syncSteps($workflow, $data['steps']);

            return $workflow;
        });

        $this->audit->log('workflow.created', "Created workflow {$workflow->name}", $workflow);

        return (new WorkflowResource($this->reload($workflow)))->response()->setStatusCode(201);
    }

    public function update(Request $request, Workflow $workflow)
    {
        $this->authorizeAdmin($request);

        $data = $this->validateWorkflow($request, $workflow);
        $this->limits->assertApprovalDepth($this->tenant->company(), $data['steps']);

        $before = ['route' => $workflow->load('steps')->routeSummary(), 'version' => $workflow->version];

        DB::transaction(function () use ($workflow, $data) {
            if ($data['is_default'] ?? false) {
                Workflow::where('is_default', true)->where('id', '!=', $workflow->id)->update(['is_default' => false]);
            }

            $changes = [
                'name' => $data['name'],
                'description' => $data['description'] ?? null,
                'is_default' => $data['is_default'] ?? $workflow->is_default,
                'is_active' => $data['is_active'] ?? $workflow->is_active,
                'version' => $workflow->version + 1,
            ];

            // Only touched when sent: a client that does not know about a field
            // must never quietly unbind a type-specific route or drop a name.
            if (array_key_exists('voucher_type_id', $data)) {
                $changes['voucher_type_id'] = $data['voucher_type_id'];
            }

            if (array_key_exists('name_sw', $data)) {
                $changes['name_sw'] = $data['name_sw'];
            }

            $workflow->update($changes);

            $this->syncSteps($workflow, $data['steps']);
        });

        $workflow = $this->reload($workflow->refresh());

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

        abort_if(
            Workflow::count() <= 1,
            422,
            'This is the company’s only workflow. Create another one before deleting it.',
        );
        abort_if(
            $workflow->is_default,
            422,
            'The default workflow cannot be deleted. Make another workflow the default first.',
        );

        $inFlight = $workflow->vouchers()->whereIn('status', self::IN_FLIGHT)->count();

        abort_if(
            $inFlight > 0,
            422,
            "{$inFlight} ".($inFlight === 1 ? 'voucher is' : 'vouchers are').' still moving through this workflow. Let them finish, or deactivate the workflow instead.',
        );
        abort_if(
            $workflow->vouchers()->exists(),
            422,
            'Completed vouchers were routed by this workflow and keep it on record. Deactivate it instead of deleting it.',
        );

        $name = $workflow->name;
        $workflow->delete();

        $this->audit->log('workflow.deleted', "Deleted workflow {$name}", $workflow);

        return response()->json(['message' => "Workflow {$name} deleted."]);
    }

    /**
     * Makes this workflow the route for every voucher type that has no route of
     * its own. The default always covers all types, and it is always active.
     */
    public function makeDefault(Request $request, Workflow $workflow)
    {
        $this->authorizeAdmin($request);

        abort_if(
            $workflow->voucher_type_id !== null,
            422,
            'A workflow bound to one voucher type cannot be the default. Set it to apply to all voucher types first.',
        );

        DB::transaction(function () use ($workflow) {
            Workflow::where('is_default', true)->where('id', '!=', $workflow->id)->update(['is_default' => false]);
            $workflow->update(['is_default' => true, 'is_active' => true]);
        });

        $this->audit->log('workflow.default_changed', "Made {$workflow->name} the default workflow", $workflow);

        return new WorkflowResource($this->reload($workflow->refresh()));
    }

    /**
     * Who approves for each department: every step of this workflow resolved
     * against every department of the company, exactly as the engine resolves
     * it for a real voucher — and every place where nobody would be found.
     */
    public function routing(Request $request, Workflow $workflow): JsonResponse
    {
        $this->authorizeAdmin($request);

        $workflow->load('steps.assignedUser');
        $companyId = $this->tenant->id();

        $departments = Department::with(['hod', 'manager'])->orderBy('name')->get();

        $steps = $workflow->steps->map(fn (WorkflowStep $step) => [
            'id' => $step->id,
            'position' => $step->position,
            'name' => $step->name,
            'name_sw' => $step->name_sw,
            'role' => $step->role,
            'role_label' => WorkflowStep::roleLabel($step->role),
            'is_request_step' => $step->isRequestStep(),
            'is_payment_step' => $step->isPaymentStep(),
            'assignment' => $this->assignmentKind($step),
            'min_amount' => $step->min_amount !== null ? (float) $step->min_amount : null,
            'max_amount' => $step->max_amount !== null ? (float) $step->max_amount : null,
        ])->values();

        $rows = $departments->map(function (Department $department) use ($workflow, $companyId) {
            $voucher = new Voucher([
                'company_id' => $companyId,
                'department_id' => $department->id,
                'workflow_id' => $workflow->id,
            ]);
            $voucher->setRelation('department', $department);

            $cells = $workflow->steps
                ->reject(fn (WorkflowStep $step) => $step->isRequestStep())
                ->map(function (WorkflowStep $step) use ($voucher, $department) {
                    $people = $this->engine->assigneesFor($voucher, $step);

                    return [
                        'step_id' => $step->id,
                        'people' => $people->map(fn (User $user) => [
                            'id' => $user->id,
                            'name' => $user->name,
                            'role' => $user->role,
                        ])->values(),
                        'gap' => $people->isEmpty() ? $this->gapReason($step, $department) : null,
                    ];
                })->values();

            return [
                'id' => $department->id,
                'name' => $department->name,
                'is_active' => (bool) $department->is_active,
                'hod' => $this->personSummary($department->hod),
                'manager' => $this->personSummary($department->manager),
                'cells' => $cells,
                'gaps' => $cells->whereNotNull('gap')->count(),
            ];
        })->values();

        return response()->json([
            'data' => [
                'workflow_id' => $workflow->id,
                'steps' => $steps,
                'departments' => $rows,
                'gaps' => $rows->sum('gaps'),
            ],
        ]);
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

        return new WorkflowResource($this->reload($workflow));
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

    /**
     * Field rules first, then the rules about the route as a whole — a route
     * that nobody can approve, or that can never be paid, is refused here
     * rather than discovered by the first voucher that gets stuck on it.
     */
    private function validateWorkflow(Request $request, ?Workflow $workflow): array
    {
        $presets = array_keys(CompanyProvisioner::PRESETS);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'name_sw' => ['nullable', 'string', 'max:120'],
            'description' => ['nullable', 'string', 'max:255'],
            'voucher_type_id' => ['nullable', 'integer', Rule::exists('voucher_types', 'id')->where('company_id', $this->tenant->id())],
            'is_default' => ['nullable', 'boolean'],
            'is_active' => ['nullable', 'boolean'],
            'from_preset' => $workflow ? ['prohibited'] : ['nullable', Rule::in($presets)],

            'steps' => [$workflow ? 'required' : 'required_without:from_preset', 'array', 'min:1', 'max:12'],
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

        if (empty($data['steps']) && ! empty($data['from_preset'])) {
            $data['steps'] = CompanyProvisioner::PRESETS[$data['from_preset']]['steps'];
        }

        unset($data['from_preset']);

        /*
         * The validated array is rebuilt key by key, and a new step (one without
         * an `id`) is only created when its `name` is reached — after every
         * existing step's `id`. Left alone, a level inserted mid-route was saved
         * at the end. The keys still carry the submitted order; restore it.
         */
        ksort($data['steps']);
        $data['steps'] = array_values($data['steps']);

        $this->assertWorkflowSettings($data, $workflow);
        $this->assertRouteIsWorkable($data['steps']);

        return $data;
    }

    /** Rules about where the workflow applies, as opposed to what it does. */
    private function assertWorkflowSettings(array $data, ?Workflow $workflow): void
    {
        $errors = [];
        $typeId = array_key_exists('voucher_type_id', $data) ? $data['voucher_type_id'] : $workflow?->voucher_type_id;
        $willBeDefault = (bool) ($data['is_default'] ?? $workflow?->is_default ?? false);
        $willBeActive = (bool) ($data['is_active'] ?? $workflow?->is_active ?? true);

        if ($willBeDefault && $typeId !== null) {
            $errors['voucher_type_id'] = 'The default workflow applies to all voucher types. Choose “All voucher types”, or make another workflow the default.';
        }

        if ($workflow?->is_default && array_key_exists('is_default', $data) && $data['is_default'] === false) {
            $errors['is_default'] = 'A company always has one default workflow. Make another workflow the default instead.';
        }

        if ($willBeDefault && ! $willBeActive) {
            $errors['is_active'] = 'The default workflow must stay active. Make another workflow the default before deactivating this one.';
        }

        if ($typeId !== null && $willBeActive) {
            $clash = Workflow::where('voucher_type_id', $typeId)
                ->where('is_active', true)
                ->when($workflow, fn ($q) => $q->where('id', '!=', $workflow->id))
                ->first();

            if ($clash) {
                $type = VoucherType::find($typeId);
                $errors['voucher_type_id'] = "The workflow “{$clash->name}” already routes {$type?->name} vouchers. Deactivate it or choose another voucher type.";
            }
        }

        if ($errors) {
            throw ValidationException::withMessages($errors);
        }
    }

    /**
     * The route must start with the requester, reach a decision and reach a
     * payment — for every amount, once amount bands are taken into account.
     *
     * @param  list<array<string, mixed>>  $steps
     */
    private function assertRouteIsWorkable(array $steps): void
    {
        $errors = [];

        if (($steps[0]['role'] ?? null) !== 'employee') {
            $errors['steps.0.role'] = 'The first step must be the request step, taken by the employee who raises the voucher.';
        }

        foreach ($steps as $index => $step) {
            $min = $step['min_amount'] ?? null;
            $max = $step['max_amount'] ?? null;

            if ($min !== null && $max !== null && (float) $min > (float) $max) {
                $errors["steps.{$index}.max_amount"] = 'Step '.($index + 1).': the upper amount limit must not be below the lower limit.';
            }

            if ($index > 0 && ($step['role'] ?? null) === 'employee') {
                $errors["steps.{$index}.role"] = 'Step '.($index + 1).': only the first step may be the requester’s own step. Choose the role that acts here.';
            }

            if ($index > 0 && ($step['role'] ?? null) === 'custom' && empty($step['assigned_user_id'])) {
                $errors["steps.{$index}.assigned_user_id"] = 'Step '.($index + 1).': a custom approver step must name the person who acts.';
            }
        }

        $later = array_slice($steps, 1);
        $approvers = array_filter($later, fn ($s) => (bool) ($s['can_approve'] ?? false));
        $payers = array_filter($later, fn ($s) => (bool) ($s['can_pay'] ?? false));

        if (! $approvers) {
            $errors['steps'] = 'At least one step must be able to approve. Otherwise no voucher on this route can ever be approved.';
        } elseif (! $this->coversEveryAmount($approvers)) {
            $errors['steps'] = 'Some amounts would reach no step that can approve. Remove the amount limits from one approving step, or close the gap between the bands.';
        } elseif (! $payers) {
            $errors['steps'] = 'At least one step must be able to pay. Otherwise approved vouchers on this route can never be paid.';
        } elseif (! $this->coversEveryAmount($payers)) {
            $errors['steps'] = 'Some amounts would reach no step that can pay. Remove the amount limits from one paying step, or close the gap between the bands.';
        }

        if ($errors) {
            throw ValidationException::withMessages($errors);
        }
    }

    /**
     * Whether the amount bands of these steps together cover every amount from
     * zero upward, to the cent.
     *
     * @param  array<int, array<string, mixed>>  $steps
     */
    private function coversEveryAmount(array $steps): bool
    {
        $bands = collect($steps)
            ->map(fn ($s) => [
                (float) ($s['min_amount'] ?? 0),
                isset($s['max_amount']) ? (float) $s['max_amount'] : INF,
            ])
            ->sortBy(fn ($band) => $band[0])
            ->values();

        $reached = 0.0;

        foreach ($bands as [$min, $max]) {
            if ($min > $reached + 0.01 + PHP_FLOAT_EPSILON) {
                return false;
            }

            $reached = max($reached, $max);

            if ($reached === INF) {
                return true;
            }
        }

        return false;
    }

    /** How a step finds its person: by department, by name, by role, or the requester. */
    private function assignmentKind(WorkflowStep $step): string
    {
        return match (true) {
            $step->isRequestStep() => 'requester',
            (bool) $step->assigned_user_id => 'named',
            $step->role === 'hod' => 'department_head',
            $step->role === 'manager' => 'department_manager',
            $step->role === 'custom' => 'unassigned',
            default => 'role',
        };
    }

    /** Why a step resolves to nobody in a department, for the routing matrix. */
    private function gapReason(WorkflowStep $step, Department $department): string
    {
        if ($step->assigned_user_id) {
            return $step->assignedUser ? 'inactive_person' : 'missing_person';
        }

        return match ($step->role) {
            'hod' => $department->hod_user_id ? 'inactive_hod' : 'no_hod',
            'manager' => $department->manager_user_id ? 'inactive_manager' : 'no_manager',
            'custom' => 'no_person_named',
            default => 'no_one_with_role',
        };
    }

    /** @return array{id:int,name:string,role:string,status:string}|null */
    private function personSummary(?User $user): ?array
    {
        return $user ? [
            'id' => $user->id,
            'name' => $user->name,
            'role' => $user->role,
            'status' => $user->status,
        ] : null;
    }

    /** Workflows with how many vouchers they carry, so the builder can explain a refused delete. */
    private function withUsage($query)
    {
        return $query->withCount([
            'vouchers',
            'vouchers as in_flight_count' => fn ($q) => $q->whereIn('status', self::IN_FLIGHT),
        ]);
    }

    private function reload(Workflow $workflow): Workflow
    {
        return $workflow->load(['steps.assignedUser', 'voucherType'])
            ->loadCount([
                'vouchers',
                'vouchers as in_flight_count' => fn ($q) => $q->whereIn('status', self::IN_FLIGHT),
            ]);
    }

    private function authorizeAdmin(Request $request): void
    {
        abort_unless($request->user()->isAdmin(), 403, 'Only an administrator may change the approval workflow.');
    }
}
