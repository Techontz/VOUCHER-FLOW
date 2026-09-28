<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherType;
use App\Models\Workflow;
use App\Models\WorkflowStep;
use App\Services\WorkflowEngine;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * An administrator configures who approves, at which level, in which order and
 * for which department — and never reaches another company's people.
 */
class WorkflowConfigurationTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private const SIGNATURE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    private function defaultWorkflow(array $t): Workflow
    {
        return Workflow::withoutGlobalScopes()
            ->where('company_id', $t['company']->id)
            ->where('is_default', true)
            ->with('steps')
            ->firstOrFail();
    }

    /** The workflow's steps as the builder sends them back. */
    private function stepsPayload(Workflow $workflow): array
    {
        return $workflow->steps->map(fn (WorkflowStep $step) => [
            'id' => $step->id,
            'name' => $step->name,
            'role' => $step->role,
            'assigned_user_id' => $step->assigned_user_id,
            'can_sign' => $step->can_sign,
            'can_approve' => $step->can_approve,
            'can_reject' => $step->can_reject,
            'can_request_changes' => $step->can_request_changes,
            'can_pay' => $step->can_pay,
            'requires_signature' => $step->requires_signature,
            'min_amount' => $step->min_amount,
            'max_amount' => $step->max_amount,
        ])->all();
    }

    private function typeId(array $t, string $code = 'payment'): int
    {
        return VoucherType::withoutGlobalScopes()
            ->where('company_id', $t['company']->id)
            ->where('code', $code)
            ->value('id');
    }

    private function saveWorkflow(array $t, Workflow $workflow, array $overrides = [])
    {
        return $this->actingAs($t['admin'], 'sanctum')->putJson("/api/workflows/{$workflow->id}", array_merge([
            'name' => $workflow->name,
            'steps' => $this->stepsPayload($workflow),
        ], $overrides));
    }

    public function test_a_step_cannot_name_a_person_from_another_company(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $zamani = $this->makeTenant('Zamani Freight');
        $workflow = $this->defaultWorkflow($acme);

        $steps = $this->stepsPayload($workflow);
        $steps[2]['assigned_user_id'] = $zamani['ceo']->id;

        $this->saveWorkflow($acme, $workflow, ['steps' => $steps])
            ->assertStatus(422)
            ->assertJsonValidationErrors('steps.2.assigned_user_id');

        $this->actingAs($acme['admin'], 'sanctum')
            ->postJson('/api/workflows', ['name' => 'Foreign', 'steps' => $steps])
            ->assertStatus(422)
            ->assertJsonValidationErrors('steps.2.assigned_user_id');
    }

    public function test_a_department_cannot_be_headed_from_another_company(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $zamani = $this->makeTenant('Zamani Freight');

        $this->actingAs($acme['admin'], 'sanctum')
            ->postJson('/api/departments', ['name' => 'Logistics', 'hod_user_id' => $zamani['hod']->id])
            ->assertStatus(422)
            ->assertJsonValidationErrors('hod_user_id');

        $this->actingAs($acme['admin'], 'sanctum')
            ->putJson("/api/departments/{$acme['department']->id}", [
                'name' => 'Operations',
                'manager_user_id' => $zamani['manager']->id,
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('manager_user_id');
    }

    public function test_reordering_and_removing_steps_keeps_their_ids(): void
    {
        $t = $this->makeTenant('Acme Trading', preset: 'finance');
        $workflow = $this->defaultWorkflow($t);
        $steps = $this->stepsPayload($workflow);
        [$request, $hod, $finance, $manager, $payment] = $steps;

        // Manager before finance; the HOD step is dropped.
        $response = $this->saveWorkflow($t, $workflow, ['steps' => [$request, $manager, $finance, $payment]])->assertOk();

        $this->assertSame(
            [$request['id'], $manager['id'], $finance['id'], $payment['id']],
            collect($response->json('data.steps'))->pluck('id')->all(),
        );
        $this->assertSame([1, 2, 3, 4], collect($response->json('data.steps'))->pluck('position')->all());
        $this->assertDatabaseMissing('workflow_steps', ['id' => $hod['id']]);
    }

    public function test_the_voucher_type_binding_survives_an_update_that_does_not_mention_it(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $default = $this->defaultWorkflow($t);
        $typeId = $this->typeId($t, 'petty_cash');

        $created = $this->actingAs($t['admin'], 'sanctum')
            ->postJson('/api/workflows', [
                'name' => 'Petty cash route',
                'name_sw' => 'Njia ya fedha taslimu',
                'voucher_type_id' => $typeId,
                'steps' => $this->stepsPayload($default),
            ])
            ->assertCreated()
            ->assertJsonPath('data.voucher_type_id', $typeId)
            ->json('data');

        $workflow = Workflow::with('steps')->find($created['id']);

        $this->saveWorkflow($t, $workflow, ['name' => 'Petty cash (renamed)'])
            ->assertOk()
            ->assertJsonPath('data.voucher_type_id', $typeId)
            ->assertJsonPath('data.name_sw', 'Njia ya fedha taslimu');

        // Sent explicitly as null, it is unbound.
        $this->saveWorkflow($t, $workflow, ['voucher_type_id' => null])
            ->assertOk()
            ->assertJsonPath('data.voucher_type_id', null);
    }

    public function test_a_type_specific_workflow_routes_only_its_own_type(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $pettyCash = $this->typeId($t, 'petty_cash');

        $created = $this->actingAs($t['admin'], 'sanctum')
            ->postJson('/api/workflows', ['name' => 'Petty cash', 'voucher_type_id' => $pettyCash, 'from_preset' => 'single'])
            ->assertCreated()
            ->assertJsonCount(2, 'data.steps');

        app(TenantContext::class)->forCompany($t['company'], function () use ($t, $pettyCash, $created) {
            $engine = app(WorkflowEngine::class);
            $this->assertSame($created->json('data.id'), $engine->resolveWorkflow(VoucherType::find($pettyCash))->id);
            $this->assertSame($this->defaultWorkflow($t)->id, $engine->resolveWorkflow(VoucherType::find($this->typeId($t)))->id);
        });

        // A second active route for the same type is refused.
        $this->actingAs($t['admin'], 'sanctum')
            ->postJson('/api/workflows', ['name' => 'Another', 'voucher_type_id' => $pettyCash, 'from_preset' => 'default'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('voucher_type_id');
    }

    public function test_amount_bands_route_large_vouchers_through_an_extra_level(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $workflow = $this->defaultWorkflow($t);

        $director = User::create([
            'company_id' => $t['company']->id, 'name' => 'Director Acme', 'email' => 'director@acme-trading.test',
            'password' => 'Password123!', 'role' => User::ROLE_DIRECTOR, 'status' => 'active',
        ]);

        $steps = $this->stepsPayload($workflow);
        array_splice($steps, 3, 0, [[
            'name' => 'Director approval', 'role' => 'director',
            'can_sign' => true, 'can_approve' => true, 'can_reject' => true,
            'requires_signature' => false, 'min_amount' => 1_000_000,
        ]]);

        $saved = $this->saveWorkflow($t, $workflow, ['steps' => $steps])->assertOk()->assertJsonCount(5, 'data.steps');

        // A level inserted mid-route is saved where it was inserted, not at the end.
        $this->assertSame(
            ['Request', 'HOD', 'Management', 'Director approval', 'Payment'],
            collect($saved->json('data.steps'))->pluck('name')->map(fn ($n) => str_starts_with($n, 'HOD') || str_starts_with($n, 'Department') ? 'HOD' : (str_starts_with($n, 'Management') ? 'Management' : $n))->all(),
        );

        $small = $this->makeVoucher($t, amount: 250_000);
        $large = $this->makeVoucher($t, amount: 5_000_000);

        foreach ([$small, $large] as $voucher) {
            $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();
            $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE])->assertOk();
            $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed")->assertOk();
            $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve")->assertOk();
        }

        $this->assertSame(Voucher::STATUS_APPROVED, $small->fresh()->status);
        $this->assertSame(Voucher::STATUS_IN_REVIEW, $large->fresh()->status);
        $this->assertSame(4, $large->fresh()->current_step_position);

        $this->actingAs($director, 'sanctum')
            ->postJson("/api/vouchers/{$large->id}/approve")
            ->assertOk()
            ->assertJsonPath('data.status', Voucher::STATUS_APPROVED);
    }

    public function test_an_unworkable_route_is_refused_with_a_reason(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $workflow = $this->defaultWorkflow($t);
        $steps = $this->stepsPayload($workflow);

        $minAboveMax = $steps;
        $minAboveMax[2]['min_amount'] = 5_000;
        $minAboveMax[2]['max_amount'] = 1_000;
        $this->saveWorkflow($t, $workflow, ['steps' => $minAboveMax])->assertStatus(422)->assertJsonValidationErrors('steps.2.max_amount');

        $noRequest = array_slice($steps, 1);
        $this->saveWorkflow($t, $workflow, ['steps' => $noRequest])->assertStatus(422)->assertJsonValidationErrors('steps.0.role');

        $noApprover = $steps;
        $noApprover[2]['can_approve'] = false;
        $this->saveWorkflow($t, $workflow, ['steps' => $noApprover])->assertStatus(422)->assertJsonValidationErrors('steps');

        $noPayer = $steps;
        $noPayer[3]['can_pay'] = false;
        $this->saveWorkflow($t, $workflow, ['steps' => $noPayer])->assertStatus(422)->assertJsonValidationErrors('steps');

        // The only approver stops at one million: bigger vouchers could never be approved.
        $gap = $steps;
        $gap[2]['max_amount'] = 1_000_000;
        $this->saveWorkflow($t, $workflow, ['steps' => $gap])->assertStatus(422)->assertJsonValidationErrors('steps');

        $this->assertSame(1, $workflow->fresh()->version, 'nothing was saved');
    }

    public function test_an_inactive_named_approver_or_head_resolves_to_nobody(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $workflow = $this->defaultWorkflow($t);
        $voucher = $this->makeVoucher($t);

        app(TenantContext::class)->forCompany($t['company'], function () use ($t, $workflow, $voucher) {
            $engine = app(WorkflowEngine::class);
            $hodStep = $workflow->steps[1];
            $ceoStep = $workflow->steps[2];

            $this->assertCount(1, $engine->assigneesFor($voucher->fresh(), $hodStep));

            $t['hod']->update(['status' => 'suspended']);
            $this->assertCount(0, $engine->assigneesFor($voucher->fresh(), $hodStep));

            $ceoStep->update(['assigned_user_id' => $t['ceo']->id]);
            $this->assertCount(1, $engine->assigneesFor($voucher->fresh(), $ceoStep->fresh()));

            $t['ceo']->update(['status' => 'suspended']);
            $this->assertCount(0, $engine->assigneesFor($voucher->fresh(), $ceoStep->fresh()));

            // The company admin's override still reaches the step.
            $this->assertTrue($engine->canActOnStep($t['admin'], $voucher->fresh(), $ceoStep->fresh()));
        });

        // And the routing matrix names the gap.
        $routing = $this->actingAs($t['admin'], 'sanctum')
            ->getJson("/api/workflows/{$workflow->id}/routing")
            ->assertOk();

        $cells = collect($routing->json('data.departments.0.cells'));
        $this->assertSame('inactive_hod', $cells->firstWhere('step_id', $workflow->steps[1]->id)['gap']);
        $this->assertSame('inactive_person', $cells->firstWhere('step_id', $workflow->steps[2]->id)['gap']);
    }

    public function test_the_routing_matrix_resolves_each_department_and_flags_gaps(): void
    {
        $acme = $this->makeTenant('Acme Trading');
        $zamani = $this->makeTenant('Zamani Freight');
        $workflow = $this->defaultWorkflow($acme);

        Department::withoutGlobalScopes()->create(['company_id' => $acme['company']->id, 'name' => 'Sales']);

        $response = $this->actingAs($acme['admin'], 'sanctum')
            ->getJson("/api/workflows/{$workflow->id}/routing")
            ->assertOk();

        $departments = collect($response->json('data.departments'));
        $this->assertSame(['Operations', 'Sales'], $departments->pluck('name')->all());

        $operations = $departments->firstWhere('name', 'Operations');
        $hodCell = collect($operations['cells'])->firstWhere('step_id', $workflow->steps[1]->id);
        $this->assertSame([$acme['hod']->id], collect($hodCell['people'])->pluck('id')->all());
        $this->assertNull($hodCell['gap']);

        $sales = $departments->firstWhere('name', 'Sales');
        $this->assertSame('no_hod', collect($sales['cells'])->firstWhere('step_id', $workflow->steps[1]->id)['gap']);

        // Nobody from another company appears anywhere in the matrix.
        $ids = $departments->flatMap(fn ($d) => collect($d['cells'])->flatMap(fn ($c) => collect($c['people'])->pluck('id')));
        $zamaniIds = User::withoutGlobalScopes()->where('company_id', $zamani['company']->id)->pluck('id');
        $this->assertEmpty($ids->intersect($zamaniIds));

        // Another company's workflow is invisible, and a non-admin is refused.
        $this->actingAs($zamani['admin'], 'sanctum')
            ->getJson("/api/workflows/{$workflow->id}/routing")
            ->assertNotFound();

        $this->actingAs($acme['employee'], 'sanctum')
            ->getJson("/api/workflows/{$workflow->id}/routing")
            ->assertForbidden();
    }

    public function test_create_delete_and_default_rules(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $default = $this->defaultWorkflow($t);

        // The only workflow cannot be deleted.
        $this->actingAs($t['admin'], 'sanctum')
            ->deleteJson("/api/workflows/{$default->id}")
            ->assertStatus(422);

        $second = $this->actingAs($t['admin'], 'sanctum')
            ->postJson('/api/workflows', ['name' => 'Finance route', 'from_preset' => 'finance'])
            ->assertCreated()
            ->assertJsonPath('data.is_default', false)
            ->json('data.id');

        // The default cannot be deleted, nor switched off without a successor.
        $this->actingAs($t['admin'], 'sanctum')->deleteJson("/api/workflows/{$default->id}")->assertStatus(422);
        $this->saveWorkflow($t, $default, ['is_default' => false])->assertStatus(422)->assertJsonValidationErrors('is_default');
        $this->saveWorkflow($t, $default, ['is_active' => false])->assertStatus(422)->assertJsonValidationErrors('is_active');

        // Only an admin may change the default.
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/workflows/{$second}/make-default")->assertForbidden();

        $this->actingAs($t['admin'], 'sanctum')
            ->postJson("/api/workflows/{$second}/make-default")
            ->assertOk()
            ->assertJsonPath('data.is_default', true);

        $this->assertFalse($default->fresh()->is_default);

        // A workflow that routed vouchers keeps its record.
        $voucher = $this->makeVoucher($t);
        $voucher->forceFill(['workflow_id' => $default->id])->save();

        $this->actingAs($t['admin'], 'sanctum')
            ->deleteJson("/api/workflows/{$default->id}")
            ->assertStatus(422)
            ->assertJsonPath('message', '1 voucher is still moving through this workflow. Let them finish, or deactivate the workflow instead.');

        $voucher->delete();

        $this->actingAs($t['admin'], 'sanctum')->deleteJson("/api/workflows/{$default->id}")->assertOk();

        // A type-bound workflow cannot become the default.
        $bound = $this->actingAs($t['admin'], 'sanctum')
            ->postJson('/api/workflows', ['name' => 'Advances', 'voucher_type_id' => $this->typeId($t, 'advance'), 'from_preset' => 'single'])
            ->assertCreated()
            ->json('data.id');

        $this->actingAs($t['admin'], 'sanctum')->postJson("/api/workflows/{$bound}/make-default")->assertStatus(422);

        // And a non-admin may not create one.
        $this->actingAs($t['employee'], 'sanctum')
            ->postJson('/api/workflows', ['name' => 'Nope', 'from_preset' => 'single'])
            ->assertForbidden();
    }
}
