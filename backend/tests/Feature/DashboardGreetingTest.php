<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * The dashboard greets by the company's clock, not the server's UTC one.
 */
class DashboardGreetingTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_an_afternoon_in_dar_es_salaam_is_greeted_as_afternoon(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['company']->update(['timezone' => 'Africa/Dar_es_Salaam']);

        // 11:00 UTC is 14:00 in Dar es Salaam.
        Carbon::setTestNow(Carbon::parse('2026-09-24 11:00:00', 'UTC'));

        $this->actingAs($t['admin'], 'sanctum')
            ->getJson('/api/dashboard')
            ->assertOk()
            ->assertJsonPath('greeting', 'Good afternoon');
    }

    public function test_an_evening_in_dar_es_salaam_is_greeted_as_evening(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $t['company']->update(['timezone' => 'Africa/Dar_es_Salaam']);

        // 15:30 UTC is 18:30 in Dar es Salaam.
        Carbon::setTestNow(Carbon::parse('2026-09-24 15:30:00', 'UTC'));

        $this->actingAs($t['admin'], 'sanctum')
            ->getJson('/api/dashboard')
            ->assertOk()
            ->assertJsonPath('greeting', 'Good evening');
    }
}
