<?php

namespace Tests\Feature;

use App\Models\Plan;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/** Every platform endpoint answers the platform operator and nobody else. */
class PlatformAccessTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function operator(): User
    {
        return User::create([
            'company_id' => null, 'name' => 'Operator', 'email' => 'super@vouchflow.test',
            'password' => 'Password123!', 'role' => User::ROLE_SUPER_ADMIN, 'status' => 'active',
        ]);
    }

    /** @return list<array{0: string, 1: string}> */
    private function endpoints(array $t): array
    {
        $c = $t['company']->id;
        $u = $t['employee']->id;
        $p = Plan::first()->id;
        $s = $t['company']->subscriptions()->withoutGlobalScopes()->first()->id;

        return [
            ['get', '/api/platform/analytics'],
            ['get', '/api/platform/settings'],
            ['put', '/api/platform/settings'],
            ['get', '/api/platform/companies'],
            ['get', "/api/platform/companies/{$c}"],
            ['put', "/api/platform/companies/{$c}/modules"],
            ['post', "/api/platform/companies/{$c}/extend"],
            ['post', "/api/platform/companies/{$c}/change-plan"],
            ['post', "/api/platform/companies/{$c}/suspend"],
            ['get', '/api/platform/plans'],
            ['post', '/api/platform/plans'],
            ['post', '/api/platform/plans/reorder'],
            ['put', "/api/platform/plans/{$p}"],
            ['delete', "/api/platform/plans/{$p}"],
            ['get', '/api/platform/subscriptions'],
            ['post', "/api/platform/subscriptions/{$s}/extend"],
            ['post', "/api/platform/subscriptions/{$s}/cancel"],
            ['post', "/api/platform/subscriptions/{$s}/reactivate"],
            ['post', "/api/platform/subscriptions/{$s}/invoice"],
            ['get', '/api/platform/payments'],
            ['get', '/api/platform/users'],
            ['get', '/api/platform/users/roles'],
            ['put', "/api/platform/users/{$u}"],
            ['post', "/api/platform/users/{$u}/invite"],
            ['post', '/api/platform/users/bulk-status'],
            ['post', '/api/platform/users/bulk-delete'],
        ];
    }

    public function test_a_company_admin_is_refused_every_platform_endpoint(): void
    {
        $t = $this->makeTenant('Acme Trading');

        foreach ($this->endpoints($t) as [$method, $uri]) {
            $this->actingAs($t['admin'], 'sanctum')
                ->json($method, $uri, [])
                ->assertStatus(403, "{$method} {$uri} should be refused");
        }
    }

    public function test_an_employee_is_refused_too(): void
    {
        $t = $this->makeTenant('Acme Trading');

        $this->actingAs($t['employee'], 'sanctum')->getJson('/api/platform/analytics')->assertForbidden();
        $this->actingAs($t['employee'], 'sanctum')->getJson('/api/platform/subscriptions')->assertForbidden();
    }

    public function test_the_operator_reaches_every_read_endpoint(): void
    {
        $t = $this->makeTenant('Acme Trading');
        $operator = $this->operator();

        foreach ($this->endpoints($t) as [$method, $uri]) {
            if ($method !== 'get') {
                continue;
            }

            $this->actingAs($operator, 'sanctum')->getJson($uri)->assertOk();
        }
    }
}
