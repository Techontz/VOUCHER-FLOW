<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Erp\Crm\Lead;
use App\Models\Erp\Customer;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * CRM: a salesperson sees only their own records, a manager everyone's;
 * converting a lead makes exactly one customer; stage moves are audited;
 * another company's records are a 404.
 */
class ErpCrmTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    /** @return array<string, mixed> */
    private function crm(string $name = 'Maji Bora'): array
    {
        $erp = $this->setUpErp($this->makeTenant($name));
        $company = $erp['company'];
        $company->forceFill(['modules' => array_values(array_unique([...($company->modules ?? []), 'crm', 'documents']))])->save();

        $make = fn (string $key) => User::create([
            'company_id' => $company->id, 'name' => ucfirst($key)." {$company->slug}",
            'email' => "{$key}@{$company->slug}.test", 'password' => 'Password123!',
            'role' => User::ROLE_SALES, 'status' => 'active',
        ]);

        return [...$erp, 'company' => $company->fresh(), 'asha' => $make('asha'), 'baraka' => $make('baraka')];
    }

    private function lead(User $as, array $data = []): int
    {
        return $this->actingAs($as, 'sanctum')->postJson('/api/erp/crm/leads', [
            'contact_name' => 'Rehema Mollel', 'company_name' => 'Mollel Wholesalers', 'phone' => '+255 754 100 200',
            'region' => 'Arusha', 'source' => 'referral', 'estimated_value' => 4500000, ...$data,
        ])->assertCreated()->json('data.id');
    }

    public function test_a_salesperson_sees_only_their_own_records_and_a_manager_sees_all(): void
    {
        $crm = $this->crm();
        $mine = $this->lead($crm['asha']);
        $theirs = $this->lead($crm['baraka'], ['contact_name' => 'Juma Said']);

        $this->actingAs($crm['asha'], 'sanctum')->getJson('/api/erp/crm/leads')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $mine);
        $this->getJson("/api/erp/crm/leads/{$theirs}")->assertNotFound();
        $this->putJson("/api/erp/crm/leads/{$theirs}", ['status' => 'contacted'])->assertNotFound();

        $deal = $this->actingAs($crm['baraka'], 'sanctum')->postJson('/api/erp/crm/opportunities', [
            'title' => 'Hotel water supply', 'value' => 12000000, 'expected_close_date' => now()->addDays(20)->toDateString(),
        ])->assertCreated()->json('data.id');

        $this->actingAs($crm['asha'], 'sanctum')->getJson('/api/erp/crm/opportunities')->assertOk()->assertJsonCount(0, 'data');
        $this->postJson("/api/erp/crm/opportunities/{$deal}/stage", ['stage' => 'proposal'])->assertNotFound();
        $this->getJson('/api/erp/crm/overview')->assertOk()->assertJsonPath('data.open_value', 0);

        // Nor can she give her own lead away, or hang an activity on his deal.
        $this->putJson("/api/erp/crm/leads/{$mine}", ['owner_id' => $crm['baraka']->id])->assertStatus(422);
        $this->postJson('/api/erp/crm/activities', ['type' => 'call', 'subject' => 'Sneak', 'opportunity_id' => $deal])->assertNotFound();

        // A manager sees both people's records and may reassign, but not edit.
        $this->actingAs($crm['manager'], 'sanctum')->getJson('/api/erp/crm/leads')->assertOk()->assertJsonCount(2, 'data');
        $this->getJson('/api/erp/crm/overview')->assertOk()->assertJsonPath('data.open_value', 12000000);
        $this->postJson("/api/erp/crm/leads/{$theirs}/assign", ['owner_id' => $crm['asha']->id])->assertOk();
        $this->postJson('/api/erp/crm/leads', ['contact_name' => 'X', 'source' => 'other'])->assertForbidden();

        $this->actingAs($crm['asha'], 'sanctum')->getJson('/api/erp/crm/leads')->assertJsonCount(2, 'data');

        // A salesperson cannot reassign at all.
        $this->postJson("/api/erp/crm/leads/{$mine}/assign", ['owner_id' => $crm['baraka']->id])->assertForbidden();

        // Someone without CRM at all is refused.
        $this->actingAs($crm['storekeeper'], 'sanctum')->getJson('/api/erp/crm/leads')->assertForbidden();
    }

    public function test_converting_a_lead_creates_exactly_one_customer_and_one_opportunity(): void
    {
        $crm = $this->crm();
        $lead = $this->lead($crm['asha']);
        $customers = fn () => app(TenantContext::class)->forCompany($crm['company'], fn () => Customer::count());
        $before = $customers();

        // Not before it is qualified.
        $this->postJson("/api/erp/crm/leads/{$lead}/convert")->assertStatus(422);
        $this->putJson("/api/erp/crm/leads/{$lead}", ['status' => 'qualified'])->assertOk();

        $result = $this->postJson("/api/erp/crm/leads/{$lead}/convert", ['title' => 'Mollel monthly supply'])
            ->assertOk()
            ->assertJsonPath('data.lead.status', 'converted')
            ->assertJsonPath('data.opportunity.stage', 'prospecting')
            ->assertJsonPath('data.opportunity.owner_id', $crm['asha']->id)
            ->json('data');

        $this->assertMatchesRegularExpression('/^CUS-\d{4}-\d{6}$/', $result['customer']['code']);
        $this->assertSame('Mollel Wholesalers', $result['customer']['name']);
        $this->assertSame((float) 4500000, (float) $result['opportunity']['value']);

        // A second conversion is refused and leaves no second customer.
        $this->postJson("/api/erp/crm/leads/{$lead}/convert")->assertStatus(422);
        $this->putJson("/api/erp/crm/leads/{$lead}", ['status' => 'qualified'])->assertStatus(422);

        $this->assertSame($before + 1, $customers());
        $this->assertSame(1, app(TenantContext::class)->forCompany($crm['company'], fn () => Lead::whereNotNull('customer_id')->count()));
        $this->getJson('/api/erp/crm/opportunities')->assertJsonCount(1, 'data');
    }

    public function test_stage_moves_are_audited_and_losing_needs_a_reason(): void
    {
        $crm = $this->crm();
        $deal = $this->actingAs($crm['asha'], 'sanctum')->postJson('/api/erp/crm/opportunities', [
            'title' => 'School water dispensers', 'value' => 8000000,
        ])->assertCreated()->assertJsonPath('data.probability', 10)->json('data.id');

        $this->postJson("/api/erp/crm/opportunities/{$deal}/stage", ['stage' => 'negotiation'])
            ->assertOk()->assertJsonPath('data.stage', 'negotiation')->assertJsonPath('data.probability', 70);

        $this->assertTrue(AuditLog::where('action', 'crm.opportunity_stage_changed')->where('entity_id', $deal)->exists());

        $this->postJson("/api/erp/crm/opportunities/{$deal}/stage", ['stage' => 'lost'])->assertStatus(422);
        $this->postJson("/api/erp/crm/opportunities/{$deal}/stage", ['stage' => 'lost', 'reason' => 'nonsense'])->assertStatus(422);
        $this->postJson("/api/erp/crm/opportunities/{$deal}/stage", ['stage' => 'won', 'reason' => 'price'])
            ->assertOk()->assertJsonPath('data.probability', 100)->assertJsonPath('data.close_reason', 'price');

        $this->getJson('/api/erp/crm/overview')->assertJsonPath('data.won_this_month.count', 1);
        $this->getJson('/api/erp/crm/win-loss')->assertOk()->assertJsonPath('data.won.0.reason', 'price')->assertJsonPath('data.win_rate', 100);
        $this->getJson("/api/erp/crm/opportunities/{$deal}")->assertOk()->assertJsonCount(3, 'data.history');
    }

    public function test_follow_ups_and_the_weighted_forecast(): void
    {
        $crm = $this->crm();
        $this->actingAs($crm['asha'], 'sanctum');
        $lead = $this->lead($crm['asha']);

        $this->postJson('/api/erp/crm/activities', ['type' => 'call', 'subject' => 'Call back', 'lead_id' => $lead, 'due_at' => now()->subDays(2)->toDateTimeString()])->assertCreated();
        $today = $this->postJson('/api/erp/crm/activities', ['type' => 'visit', 'subject' => 'Site visit', 'due_at' => today()->setTime(15, 0)->toDateTimeString()])->assertCreated()->json('data.id');

        $this->getJson('/api/erp/crm/overview')->assertOk()
            ->assertJsonPath('data.overdue_count', 1)->assertJsonPath('data.due_today_count', 1);

        $this->postJson("/api/erp/crm/activities/{$today}/complete", ['outcome' => 'Agreed a trial order'])->assertOk();
        $this->postJson("/api/erp/crm/activities/{$today}/complete")->assertStatus(422);
        $this->getJson('/api/erp/crm/overview')->assertJsonPath('data.due_today_count', 0);
        $this->getJson('/api/erp/crm/activities?status=overdue')->assertJsonCount(1, 'data');

        $this->postJson('/api/erp/crm/opportunities', ['title' => 'A', 'value' => 1000000, 'stage' => 'proposal', 'expected_close_date' => now()->startOfMonth()->addDays(3)->toDateString()])->assertCreated();
        $this->postJson('/api/erp/crm/opportunities', ['title' => 'B', 'value' => 2000000, 'expected_close_date' => now()->startOfMonth()->addMonth()->addDays(3)->toDateString()])->assertCreated();

        $forecast = $this->getJson('/api/erp/crm/forecast')->assertOk()->json('data');
        $this->assertSame(1000000.0, (float) $forecast['months'][0]['value']);
        $this->assertSame(400000.0, (float) $forecast['months'][0]['weighted']);
        $this->assertSame(200000.0, (float) $forecast['months'][1]['weighted']);
        $this->assertSame(600000.0, (float) $forecast['total']['weighted']);
    }

    public function test_another_companys_crm_records_are_invisible(): void
    {
        $mine = $this->crm('Maji Bora');
        $theirs = $this->crm('Zamani Freight');
        $lead = $this->lead($theirs['asha']);
        $deal = $this->actingAs($theirs['admin'], 'sanctum')->postJson('/api/erp/crm/opportunities', ['title' => 'Theirs', 'value' => 5])->assertCreated()->json('data.id');

        $this->actingAs($mine['admin'], 'sanctum');
        $this->getJson("/api/erp/crm/leads/{$lead}")->assertNotFound();
        $this->postJson("/api/erp/crm/leads/{$lead}/convert")->assertNotFound();
        $this->getJson("/api/erp/crm/opportunities/{$deal}")->assertNotFound();
        $this->postJson("/api/erp/crm/opportunities/{$deal}/stage", ['stage' => 'won'])->assertNotFound();
        $this->getJson('/api/erp/crm/leads')->assertJsonCount(0, 'data');
        $this->postJson('/api/erp/crm/leads', ['contact_name' => 'X', 'source' => 'other', 'owner_id' => $theirs['asha']->id])
            ->assertStatus(422)->assertJsonValidationErrors('owner_id');
    }

    public function test_crm_is_refused_when_the_module_is_off(): void
    {
        $erp = $this->setUpErp($this->makeTenant('Maji Bora'));

        $this->actingAs($erp['admin'], 'sanctum')->getJson('/api/erp/crm/leads')
            ->assertForbidden()->assertJsonPath('code', 'module_disabled');
    }
}
