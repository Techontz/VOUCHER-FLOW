<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\AuditLog;
use App\Models\Company;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherTemplateChange;
use App\Models\VoucherType;
use App\Support\VoucherTemplates;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Voucher designs: chosen at registration, changeable once by the company,
 * changeable any time by the platform — and never allowed to rewrite a
 * document that has already been issued.
 */
class VoucherTemplateTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private const SIGNATURE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    private function superAdmin(): User
    {
        return User::create([
            'name' => 'Platform Operator', 'email' => 'operator@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);
    }

    private function register(array $extra = [])
    {
        $this->seedPlans();

        return $this->postJson('/api/auth/register', [
            'company_name' => 'Kilimanjaro Logistics',
            'business_email' => 'accounts@kilimanjaro.test',
            'name' => 'Frank Joseph',
            'email' => 'frank@kilimanjaro.test',
            'password' => 'Password123!',
            'password_confirmation' => 'Password123!',
        ] + $extra);
    }

    public function test_the_catalogue_offers_ten_designs_publicly(): void
    {
        $this->getJson('/api/voucher-templates')
            ->assertOk()
            ->assertJsonCount(10, 'data')
            ->assertJsonPath('default', VoucherTemplates::DEFAULT)
            ->assertJsonPath('self_service_changes', 1);
    }

    public function test_every_design_renders_the_sample_in_the_typed_brand(): void
    {
        $response = $this->postJson('/api/voucher-templates/preview', [
            'name' => 'Northwind Traders',
            'primary_color' => '#C2410C',
            'with_logo' => true,
        ])->assertOk();

        $this->assertCount(count(VoucherTemplates::keys()), $response->json('data'));

        foreach ($response->json('data') as $preview) {
            $this->assertStringContainsString('Northwind Traders', $preview['html'], $preview['key']);
            $this->assertStringContainsString('PV-2026-00124', $preview['html'], $preview['key']);
            $this->assertStringContainsString('#C2410C', $preview['html'], $preview['key']);
            $this->assertStringContainsString($response->json('logo_placeholder'), $preview['html'], $preview['key']);
        }
    }

    public function test_every_design_prints_a_real_voucher_as_a_pdf(): void
    {
        $t = $this->makeTenant('Watercom Demo');
        $voucher = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit");

        foreach (VoucherTemplates::keys() as $key) {
            $voucher->forceFill(['voucher_template' => $key])->save();

            $pdf = $this->actingAs($t['employee'], 'sanctum')
                ->get("/api/vouchers/{$voucher->id}/pdf")
                ->assertOk()
                ->getContent();

            $this->assertStringStartsWith('%PDF', $pdf, $key);
        }
    }

    public function test_registration_saves_the_chosen_design_without_spending_a_change(): void
    {
        $this->register(['voucher_template' => 'executive'])
            ->assertCreated()
            ->assertJsonPath('company.voucher_template', 'executive');

        $company = Company::where('name', 'Kilimanjaro Logistics')->firstOrFail();

        $this->assertSame('executive', $company->voucher_template);
        $this->assertSame(0, (int) $company->voucher_template_changes_used);

        $change = VoucherTemplateChange::where('company_id', $company->id)->sole();
        $this->assertSame(VoucherTemplateChange::SOURCE_REGISTRATION, $change->source);
        $this->assertNull($change->previous_template);
        $this->assertFalse($change->counted);
        $this->assertSame('Frank Joseph', $change->changed_by_name);
    }

    public function test_registration_defaults_and_refuses_unknown_designs(): void
    {
        $this->register(['voucher_template' => 'comic-sans'])->assertUnprocessable()->assertJsonValidationErrors('voucher_template');

        $this->register()->assertCreated()->assertJsonPath('company.voucher_template', VoucherTemplates::DEFAULT);
    }

    public function test_a_company_admin_can_change_the_design_exactly_once(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['admin'], 'sanctum')->getJson('/api/company/voucher-template')
            ->assertOk()
            ->assertJsonPath('template', 'classic')
            ->assertJsonPath('changes_remaining', 1);

        $this->actingAs($t['admin'], 'sanctum')
            ->putJson('/api/company/voucher-template', ['template' => 'modern'])
            ->assertOk()
            ->assertJsonPath('template', 'modern')
            ->assertJsonPath('changes_used', 1)
            ->assertJsonPath('changes_remaining', 0)
            ->assertJsonPath('history.0.previous_template', 'classic')
            ->assertJsonPath('history.0.new_template', 'modern')
            ->assertJsonPath('history.0.changed_by_role', 'company_admin');

        // The second attempt is refused by the server, whatever the client shows.
        $this->actingAs($t['admin'], 'sanctum')
            ->putJson('/api/company/voucher-template', ['template' => 'executive'])
            ->assertForbidden();

        $company = $t['company']->fresh();
        $this->assertSame('modern', $company->voucher_template);
        $this->assertSame(1, (int) $company->voucher_template_changes_used);
        $this->assertSame(1, VoucherTemplateChange::where('company_id', $company->id)->count());
        $this->assertTrue(AuditLog::where('action', 'company.voucher_template_changed')->where('company_id', $company->id)->exists());
    }

    public function test_choosing_the_current_design_does_not_spend_the_change(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['admin'], 'sanctum')
            ->putJson('/api/company/voucher-template', ['template' => 'classic'])
            ->assertUnprocessable();

        $this->assertSame(0, (int) $t['company']->fresh()->voucher_template_changes_used);
    }

    public function test_only_the_company_admin_may_change_the_design(): void
    {
        $t = $this->makeTenant('Acme Trading');

        foreach (['employee', 'hod', 'ceo', 'cashier', 'finance'] as $who) {
            $this->actingAs($t[$who], 'sanctum')
                ->putJson('/api/company/voucher-template', ['template' => 'modern'])
                ->assertForbidden();
        }

        $this->assertSame(0, (int) $t['company']->fresh()->voucher_template_changes_used);
    }

    public function test_the_design_cannot_be_smuggled_in_through_other_company_endpoints(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['admin'], 'sanctum')->putJson('/api/company', [
            'voucher_template' => 'formal', 'voucher_template_changes_used' => 0,
        ])->assertOk();

        $this->actingAs($t['admin'], 'sanctum')->postJson('/api/company/branding', [
            'voucher_template' => 'formal', 'primary_color' => '#112233',
        ])->assertOk();

        $this->assertSame('classic', $t['company']->fresh()->voucher_template);
    }

    public function test_a_company_admin_cannot_use_the_platform_override(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['admin'], 'sanctum')
            ->putJson("/api/platform/companies/{$t['company']->id}/voucher-template", ['template' => 'formal'])
            ->assertForbidden();

        $this->assertSame('classic', $t['company']->fresh()->voucher_template);
    }

    public function test_the_super_admin_can_change_the_design_after_the_limit_without_spending_it(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $operator = $this->superAdmin();

        $this->actingAs($t['admin'], 'sanctum')->putJson('/api/company/voucher-template', ['template' => 'modern'])->assertOk();

        $this->actingAs($operator, 'sanctum')
            ->putJson("/api/platform/companies/{$t['company']->id}/voucher-template", [
                'template' => 'executive', 'reason' => 'Board requested a formal letterhead',
            ])
            ->assertOk()
            ->assertJsonPath('template', 'executive')
            ->assertJsonPath('changes_used', 1)
            ->assertJsonPath('changes_remaining', 0)
            ->assertJsonPath('history.0.source', 'super_admin')
            ->assertJsonPath('history.0.changed_by_name', 'Platform Operator')
            ->assertJsonPath('history.0.reason', 'Board requested a formal letterhead')
            ->assertJsonPath('history.1.source', 'company_admin');

        $this->actingAs($operator, 'sanctum')
            ->getJson("/api/platform/companies/{$t['company']->id}/voucher-template")
            ->assertOk()
            ->assertJsonCount(2, 'history');

        $this->actingAs($operator, 'sanctum')
            ->postJson("/api/platform/companies/{$t['company']->id}/voucher-template/preview", ['template' => 'executive'])
            ->assertOk()
            ->assertJsonPath('data.0.key', 'executive');
    }

    public function test_issued_documents_keep_their_design_when_the_company_changes_it(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $issued = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$issued->id}/submit");
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$issued->id}/sign", ['signature' => self::SIGNATURE]);
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$issued->id}/submit-signed");
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$issued->id}/approve");
        $this->assertSame(Voucher::STATUS_APPROVED, $issued->fresh()->status);

        $moving = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$moving->id}/submit");

        $this->actingAs($t['admin'], 'sanctum')->putJson('/api/company/voucher-template', ['template' => 'minimal'])->assertOk();

        $this->actingAs($t['employee'], 'sanctum')->getJson("/api/vouchers/{$issued->id}/document")
            ->assertOk()->assertJsonPath('template', 'classic');

        $this->actingAs($t['employee'], 'sanctum')->getJson("/api/vouchers/{$moving->id}/document")
            ->assertOk()->assertJsonPath('template', 'minimal');

        $fresh = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')->getJson("/api/vouchers/{$fresh->id}/document")
            ->assertOk()->assertJsonPath('template', 'minimal');
    }

    public function test_one_companys_document_is_not_readable_by_another(): void
    {
        $alpha = $this->makeTenant('Alpha Ltd');
        $beta = $this->makeTenant('Beta Ltd');
        $voucher = $this->makeVoucher($alpha);

        $this->actingAs($beta['admin'], 'sanctum')
            ->getJson("/api/vouchers/{$voucher->id}/document")
            ->assertNotFound();

        $this->actingAs($beta['admin'], 'sanctum')->putJson('/api/company/voucher-template', ['template' => 'formal'])->assertOk();
        $this->assertSame('classic', $alpha['company']->fresh()->voucher_template);
        $this->assertSame('formal', $beta['company']->fresh()->voucher_template);
    }

    public function test_after_the_change_is_spent_the_admin_can_ask_the_platform(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $operator = $this->superAdmin();

        $this->actingAs($t['admin'], 'sanctum')->putJson('/api/company/voucher-template', ['template' => 'modern'])->assertOk();

        $this->actingAs($t['employee'], 'sanctum')
            ->postJson('/api/company/voucher-template/request', ['template' => 'formal', 'reason' => 'Auditors want boxes'])
            ->assertForbidden();

        $this->actingAs($t['admin'], 'sanctum')
            ->postJson('/api/company/voucher-template/request', ['template' => 'formal', 'reason' => 'Auditors want boxes'])
            ->assertOk();

        $this->assertTrue(AppNotification::where('user_id', $operator->id)
            ->where('type', 'voucher_template.change_requested')
            ->where('action_url', "/platform/companies/{$t['company']->id}")
            ->exists());

        // Asking changes nothing by itself.
        $this->assertSame('modern', $t['company']->fresh()->voucher_template);
    }

    public function test_a_draft_being_written_previews_in_the_companys_design(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['company']->forceFill(['voucher_template' => 'enterprise'])->save();
        $type = VoucherType::acrossTenants()->where('company_id', $t['company']->id)->firstOrFail();

        $response = $this->actingAs($t['employee'], 'sanctum')
            ->postJson('/api/vouchers/document-preview', [
                'voucher_type_id' => $type->id,
                'payee' => 'Puma Energy', 'purpose' => 'Diesel for the fleet', 'amount' => 450000, 'kind' => 'cash',
            ])
            ->assertOk()
            ->assertJsonPath('template', 'enterprise');

        $this->assertStringContainsString('Diesel for the fleet', $response->json('html'));
        $this->assertSame(0, Voucher::acrossTenants()->count(), 'A preview must never save a voucher.');
    }

    /** Readability is a rule: no design may set anything below 7.5pt. */
    public function test_no_design_uses_type_smaller_than_seven_and_a_half_points(): void
    {
        $document = app(\App\Services\VoucherDocument::class);

        foreach (VoucherTemplates::keys() as $key) {
            $html = $document->renderSample($key, [], 'en', 'pdf');
            preg_match_all('/font-size:\s*([\d.]+)(pt|px)/', $html, $m, PREG_SET_ORDER);
            $sizes = array_filter(array_map(fn ($x) => $x[2] === 'px' ? $x[1] * 0.75 : (float) $x[1], $m), fn ($x) => $x > 0);

            $this->assertGreaterThanOrEqual(7.5, min($sizes), "{$key} sets text below 7.5pt");
        }
    }
}
