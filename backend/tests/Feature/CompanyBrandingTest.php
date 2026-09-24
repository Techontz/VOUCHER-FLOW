<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * What the branding screen sends, end to end.
 *
 * The screen once sent PUT to /company/branding, a POST-only route, so every
 * save failed in production while the in-browser mock accepted it. The text
 * fields go to PUT /company and artwork to /company/logo; these tests pin both.
 */
class CompanyBrandingTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    public function test_an_admin_saves_profile_bank_and_colours_in_one_request(): void
    {
        $t = $this->makeTenant('Watercom');

        $this->actingAs($t['admin'], 'sanctum')
            ->putJson('/api/company', [
                'name' => 'Watercom (T) Limited',
                'legal_name' => 'WATERCOM (T) LIMITED',
                'address' => 'P.O. Box 20831, Kilwa Road',
                'phone' => '+255 22 214 0831',
                'email' => 'info@watercom.co.tz',
                'website' => 'www.watercom.co.tz',
                'tin' => '101-482-771',
                'primary_color' => '#2E3192',
                'color_theme' => 'emerald',
                'voucher_footer_text' => 'Thank you.',
                'bank_name' => 'CRDB Bank',
                'bank_branch' => 'Tower Branch',
                'bank_account_name' => 'WATERCOM T LIMITED',
                'bank_account_number' => '0250390569500',
            ])
            ->assertOk()
            ->assertJsonPath('data.name', 'Watercom (T) Limited')
            ->assertJsonPath('data.tin', '101-482-771')
            ->assertJsonPath('data.bank_branch', 'Tower Branch')
            ->assertJsonPath('data.color_theme', 'emerald');

        $this->assertSame('0250390569500', $t['company']->fresh()->bank_account_number);
    }

    public function test_new_companies_start_on_the_crimson_interface_theme(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['admin'], 'sanctum')
            ->getJson('/api/company')
            ->assertOk()
            ->assertJsonPath('data.color_theme', 'crimson');
    }

    public function test_a_company_can_still_choose_the_blue_interface_theme(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['admin'], 'sanctum')
            ->putJson('/api/company', ['color_theme' => 'blue'])
            ->assertOk()
            ->assertJsonPath('data.color_theme', 'blue');
    }

    public function test_an_unknown_colour_theme_is_refused(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['admin'], 'sanctum')
            ->putJson('/api/company', ['color_theme' => 'neon'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('color_theme');
    }

    public function test_an_employee_cannot_rebrand_the_company(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['employee'], 'sanctum')
            ->putJson('/api/company', ['color_theme' => 'rose'])
            ->assertForbidden();

        $this->assertSame('crimson', $t['company']->fresh()->color_theme);
    }

    public function test_both_logos_can_be_replaced_and_removed(): void
    {
        Storage::fake('public');
        $t = $this->makeTenant('Acme Trading');

        foreach (['logo', 'logo_mark'] as $slot) {
            $this->actingAs($t['admin'], 'sanctum')
                ->post('/api/company/logo', [
                    'logo' => UploadedFile::fake()->image("{$slot}.png", 400, 120),
                    'slot' => $slot,
                ], ['Accept' => 'application/json'])
                ->assertOk();
        }

        $company = $t['company']->fresh();
        $this->assertNotNull($company->logo_path);
        $this->assertNotNull($company->logo_mark_path);

        $this->actingAs($t['admin'], 'sanctum')
            ->deleteJson('/api/company/logo?slot=logo_mark')
            ->assertOk();

        $this->assertNull($t['company']->fresh()->logo_mark_path);
    }
}
