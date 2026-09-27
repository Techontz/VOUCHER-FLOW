<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Voucher;
use App\Models\Workflow;
use App\Models\WorkflowStep;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Each role's dashboard: the attention banner, the figures (by stable key) and
 * recent activity — all computed from vouchers the caller may see, and never
 * from another company's.
 */
class RoleDashboardTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private const SIGNATURE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    /* -------------------------------------------------------------- helpers */

    private function dashboard(User $user): TestResponse
    {
        return $this->actingAs($user, 'sanctum')->getJson('/api/dashboard')->assertOk();
    }

    /** @return array<string,array> figures keyed by their stable key (first of each). */
    private function stats(TestResponse $response): array
    {
        $out = [];

        foreach ($response->json('data.stats') as $stat) {
            $out[$stat['key']] ??= $stat;
        }

        return $out;
    }

    private function submit(array $t, Voucher $v): void
    {
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$v->id}/submit")->assertOk();
    }

    private function sign(array $t, Voucher $v): void
    {
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$v->id}/sign", ['signature' => self::SIGNATURE])->assertOk();
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$v->id}/submit-signed")->assertOk();
    }

    private function approve(array $t, Voucher $v): void
    {
        $this->submit($t, $v);
        $this->sign($t, $v);
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$v->id}/approve")->assertOk();
    }

    private function pay(array $t, Voucher $v): void
    {
        $this->approve($t, $v);
        $this->actingAs($t['cashier'], 'sanctum')->postJson("/api/vouchers/{$v->id}/pay", ['payment_reference' => 'TRX-1'])->assertOk();
    }

    private function reject(array $t, Voucher $v): void
    {
        $this->submit($t, $v);
        $this->sign($t, $v);
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$v->id}/reject", ['comment' => 'Not budgeted'])->assertOk();
    }

    /* ------------------------------------------------------------- employee */

    public function test_employee_dashboard_counts_their_own_vouchers(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->makeVoucher($t, amount: 100);                         // draft
        $this->submit($t, $this->makeVoucher($t, amount: 200));      // pending
        $this->pay($t, $this->makeVoucher($t, amount: 300));         // paid
        $this->reject($t, $this->makeVoucher($t, amount: 400));      // rejected

        $response = $this->dashboard($t['employee']);
        $stats = $this->stats($response);

        $response->assertJsonPath('data.view', 'employee')
            ->assertJsonPath('data.banner.count', 1)
            ->assertJsonPath('data.banner.key', 'dash.banner.pending.one')
            ->assertJsonPath('data.banner.title', 'You have 1 voucher waiting for your attention.')
            ->assertJsonPath('data.banner.action.href', '#queue');

        $this->assertSame('4', $stats['dash.stat.myVouchers']['value']);
        $this->assertSame('1', $stats['dash.stat.pending']['value']);
        $this->assertSame('0', $stats['dash.stat.approved']['value']);
        $this->assertSame('1', $stats['dash.stat.rejected']['value']);
        $this->assertSame('1', $stats['dash.stat.paidVouchers']['value']);
        $this->assertSame('TZS 900', $stats['dash.stat.amountRaised']['value']);
        $this->assertSame('Amount raised', $stats['dash.stat.amountRaised']['label']);

        $activity = $response->json('data.recent_activity');
        $this->assertNotEmpty($activity);
        $this->assertSame('dash.activity.mine', $response->json('data.recent_activity_key'));
        $this->assertContains('paid', array_column($activity, 'action'));
    }

    public function test_employee_with_nothing_to_do_gets_the_clear_state(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $this->submit($t, $this->makeVoucher($t));

        $this->dashboard($t['employee'])
            ->assertJsonPath('data.banner.count', 0)
            ->assertJsonPath('data.banner.title', 'Nothing needs your attention.')
            ->assertJsonPath('data.banner.body_key', 'dash.banner.clear.employee')
            ->assertJsonPath('data.banner.body', "Everything you've submitted is currently being processed or has already been reviewed.")
            ->assertJsonPath('data.banner.action', null);
    }

    /* ------------------------------------------------------------------ hod */

    public function test_hod_dashboard_counts_signatures_and_includes_paid_value(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $waiting = $this->makeVoucher($t, amount: 150);
        $this->submit($t, $waiting);

        $response = $this->dashboard($t['hod']);
        $stats = $this->stats($response);

        $response->assertJsonPath('data.view', 'hod')
            ->assertJsonPath('data.banner.count', 1)
            ->assertJsonPath('data.banner.action.key', 'dash.cta.sign');
        $this->assertSame('1', $stats['dash.stat.awaitingSignature']['value']);
        $this->assertSame('0', $stats['dash.stat.signedThisMonth']['value']);

        // One approved and one paid: both are department spend.
        $this->approve($t, $this->makeVoucher($t, amount: 1000));
        $this->pay($t, $this->makeVoucher($t, amount: 2000));

        $stats = $this->stats($this->dashboard($t['hod']));
        $this->assertSame('2', $stats['dash.stat.signedThisMonth']['value']);
        $this->assertSame('3', $stats['dash.stat.deptVouchersThisMonth']['value']);
        $this->assertSame('TZS 3,000', $stats['dash.stat.deptValue']['value']);
        $this->assertSame('Operations expenses', $stats['dash.stat.deptExpenses']['label']);
        $this->assertSame('Operations', $stats['dash.stat.deptExpenses']['params']['department']);
        $this->assertSame('TZS 3,000', $stats['dash.stat.deptExpenses']['value']);

        $this->assertArrayNotHasKey('dash.stat.awaitingApproval', $stats, 'An HOD signs; nothing here implies they approve.');
    }

    public function test_hod_clear_state_speaks_of_signatures(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->dashboard($t['hod'])
            ->assertJsonPath('data.banner.body', 'No vouchers are waiting for your signature.');
    }

    public function test_hod_actions_sign_and_request_changes_but_never_approve(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($t);
        $this->submit($t, $voucher);

        $step = WorkflowStep::whereHas('workflow', fn ($w) => $w->where('company_id', $t['company']->id)->where('is_default', true))
            ->where('position', 2)->firstOrFail();
        $this->assertSame('HOD signature', $step->name);

        $actions = $this->actingAs($t['hod'], 'sanctum')->getJson("/api/vouchers/{$voucher->id}")->assertOk()->json('data.actions');

        $this->assertTrue($actions['sign']);
        $this->assertFalse($actions['approve']);
        $this->assertSame((bool) $step->can_reject, $actions['reject']);
        $this->assertFalse($actions['reject']);
        $this->assertSame((bool) $step->can_request_changes, $actions['request_changes']);
    }

    /* ------------------------------------------------------------- approver */

    public function test_approver_dashboard_counts_their_decisions(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $waiting = $this->makeVoucher($t, amount: 50);
        $this->submit($t, $waiting);
        $this->sign($t, $waiting);

        $this->pay($t, $this->makeVoucher($t, amount: 700));
        $this->reject($t, $this->makeVoucher($t, amount: 80));

        $response = $this->dashboard($t['ceo']);
        $stats = $this->stats($response);

        $response->assertJsonPath('data.view', 'approver')
            ->assertJsonPath('data.banner.count', 1)
            ->assertJsonPath('data.banner.title', 'You have 1 voucher waiting for your attention.');

        $this->assertSame('1', $stats['dash.stat.awaitingApproval']['value']);
        $this->assertSame('1', $stats['dash.stat.approvedThisMonth']['value']);
        $this->assertSame('1', $stats['dash.stat.rejectedThisMonth']['value']);
        $this->assertSame('TZS 700', $stats['dash.stat.totalValue']['value']);

        $departments = $response->json('data.by_department');
        $this->assertSame('Operations', $departments[0]['name']);
        $this->assertEquals(700, $departments[0]['total'], 'A paid voucher is still department spending.');
    }

    public function test_approver_clear_state_speaks_of_approval(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->dashboard($t['ceo'])
            ->assertJsonPath('data.banner.count', 0)
            ->assertJsonPath('data.banner.body', 'No vouchers are waiting for your approval.');
    }

    /* -------------------------------------------------------------- cashier */

    public function test_cashier_dashboard_tracks_payments(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->approve($t, $this->makeVoucher($t, amount: 500));
        $this->pay($t, $this->makeVoucher($t, amount: 900));

        $response = $this->dashboard($t['cashier']);
        $stats = $this->stats($response);

        $response->assertJsonPath('data.view', 'cashier')
            ->assertJsonPath('data.banner.count', 1)
            ->assertJsonPath('data.payment_totals.paid.count', 1)
            ->assertJsonPath('data.payment_totals.bank.count', 1);

        $this->assertSame('1', $stats['dash.stat.awaitingPayment']['value']);
        $this->assertSame('TZS 500', $stats['dash.stat.pendingPayments']['value']);
        $this->assertSame('1', $stats['dash.stat.paidVouchers']['value']);
        $this->assertSame('TZS 900', $stats['dash.stat.paidThisMonth']['value']);
        $this->assertSame(['paid'], array_values(array_unique(array_column($response->json('data.recent_activity'), 'action'))));
    }

    public function test_cashier_clear_state(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->dashboard($t['cashier'])
            ->assertJsonPath('data.banner.body', 'Every approved voucher has been paid.');
    }

    /* ---------------------------------------------------------------- admin */

    public function test_admin_dashboard_shows_the_company_overview(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $this->approve($t, $this->makeVoucher($t, amount: 100));
        $this->pay($t, $this->makeVoucher($t, amount: 200));

        $response = $this->dashboard($t['admin']);
        $stats = $this->stats($response);

        $response->assertJsonPath('data.view', 'admin')
            ->assertJsonPath('data.banner.body', 'No vouchers have stalled in the workflow.')
            ->assertJsonPath('data.overview.departments', 1)
            ->assertJsonPath('data.subscription.status', $t['company']->fresh()->status);

        $this->assertSame('2', $stats['dash.stat.approvedIncludingPaid']['value'], 'Paid vouchers were approved too.');
        $this->assertSame('1', $stats['dash.stat.paidVouchers']['value']);
        $this->assertSame(
            ['Request', 'HOD signature', 'Management approval', 'Payment'],
            array_column($response->json('data.workflow.steps'), 'name'),
        );
        $this->assertSame(
            ['request', 'sign', 'approve', 'pay'],
            array_column($response->json('data.workflow.steps'), 'action'),
        );
        $this->assertNotEmpty($response->json('data.volume'));
    }

    /* ------------------------------------------------------ tenant isolation */

    public function test_another_companys_vouchers_are_never_counted(): void
    {
        $a = $this->makeTenant('Acme Trading');
        $b = $this->makeTenant('Zamani Freight');

        $this->pay($b, $this->makeVoucher($b, amount: 5000));
        $this->approve($b, $this->makeVoucher($b, amount: 7000));

        $admin = $this->stats($this->dashboard($a['admin']));
        $this->assertSame('0', $admin['dash.stat.submittedVouchers']['value']);
        $this->assertSame('0', $admin['dash.stat.paidVouchers']['value']);

        $cashier = $this->dashboard($a['cashier']);
        $this->assertSame('0', $this->stats($cashier)['dash.stat.awaitingPayment']['value']);
        $this->assertSame([], $cashier->json('data.recent_activity'));

        $ceo = $this->stats($this->dashboard($a['ceo']));
        $this->assertSame('0', $ceo['dash.stat.approvedThisMonth']['value']);

        $this->assertSame([], $this->dashboard($a['hod'])->json('data.recent_activity'));
    }

    /* ------------------------------------------------------------- platform */

    public function test_platform_dashboard_still_renders(): void
    {
        $this->makeTenant('Acme Trading');

        $super = User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);

        $this->dashboard($super)
            ->assertJsonPath('data.view', 'platform')
            ->assertJsonPath('data.stats.0.key', 'dash.stat.totalCompanies');
    }

    /* ------------------------------------------------------------ migration */

    public function test_existing_department_review_steps_are_renamed(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $workflow = Workflow::withoutGlobalScopes()->where('company_id', $t['company']->id)->where('is_default', true)->firstOrFail();

        DB::table('workflow_steps')->where('workflow_id', $workflow->id)->where('position', 2)
            ->update(['name' => 'Department review', 'name_sw' => 'Ukaguzi wa idara']);
        // A deciding step that happens to share the name is the admin's own choice.
        DB::table('workflow_steps')->where('workflow_id', $workflow->id)->where('position', 3)
            ->update(['name' => 'Department review']);

        $migration = require database_path('migrations/2026_09_27_150000_rename_department_review_steps_to_hod_signature.php');
        $migration->up();

        $steps = DB::table('workflow_steps')->where('workflow_id', $workflow->id)->orderBy('position')->get();
        $this->assertSame('HOD signature', $steps[1]->name);
        $this->assertSame('Sahihi ya Mkuu wa Idara', $steps[1]->name_sw);
        $this->assertSame('Department review', $steps[2]->name);
    }
}
