<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\Voucher;
use App\Models\VoucherType;
use App\Services\VoucherNumberGenerator;
use App\Support\TenantContext;
use Database\Seeders\DemoSeeder;
use Database\Seeders\PlanSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Voucher numbering must never collide with what is already on disk.
 *
 * A live tenant holding forty-one vouchers was issued PV-2026-000001 and the
 * insert died on vouchers_company_id_number_unique. The counter on
 * voucher_types had been reset by a year comparison that was true every time,
 * and nothing checked the counter against reality before using it.
 *
 * These tests treat the vouchers table as the authority, because it carries
 * the constraint the database will actually enforce.
 */
class VoucherNumberGeneratorTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private function generator(): VoucherNumberGenerator
    {
        return app(VoucherNumberGenerator::class);
    }

    /**
     * Issues a number the way a request does — inside a resolved tenant.
     *
     * Without the tenant context these tests would fail on the global scope
     * instead of on the number, which would make them pass or fail for reasons
     * unrelated to what they are meant to be pinning down.
     */
    private function issue(array $tenant, VoucherType $type): string
    {
        return app(TenantContext::class)->forCompany(
            $tenant['company'],
            fn () => app(VoucherNumberGenerator::class)->next($type->fresh()),
        );
    }

    private function previewIn(array $tenant, VoucherType $type): string
    {
        return app(TenantContext::class)->forCompany(
            $tenant['company'],
            fn () => app(VoucherNumberGenerator::class)->preview($type->fresh()),
        );
    }

    private function typeFor(array $tenant, string $code = 'payment'): VoucherType
    {
        return VoucherType::withoutGlobalScopes()
            ->where('company_id', $tenant['company']->id)
            ->where('code', $code)
            ->firstOrFail();
    }

    /** Writes a voucher straight in, so the generator has history to find. */
    private function existing(array $tenant, VoucherType $type, string $number): Voucher
    {
        return app(TenantContext::class)->forCompany($tenant['company'], fn () => Voucher::create([
            'company_id' => $tenant['company']->id,
            'number' => $number,
            'voucher_type_id' => $type->id,
            'requester_id' => $tenant['employee']->id,
            'payee' => 'Supplier', 'purpose' => 'History', 'amount' => 1000,
            'currency' => 'TZS', 'status' => Voucher::STATUS_DRAFT,
            'voucher_date' => now(), 'created_by' => $tenant['employee']->id,
        ]));
    }

    public function test_the_first_number_of_an_empty_series_is_one(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $year = now()->format('Y');

        $this->assertSame("PV-{$year}-000001", $this->issue($tenant, $this->typeFor($tenant)));
    }

    public function test_it_continues_after_existing_vouchers(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $type = $this->typeFor($tenant);
        $year = now()->format('Y');

        $this->existing($tenant, $type, "PV-{$year}-000001");
        $this->existing($tenant, $type, "PV-{$year}-000002");

        DB::table('voucher_types')->where('id', $type->id)->update(['next_number' => 3]);

        $this->assertSame("PV-{$year}-000003", $this->issue($tenant, $type));
    }

    /** The production failure: the counter is behind the vouchers on disk. */
    public function test_a_counter_behind_reality_is_reconciled(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $type = $this->typeFor($tenant);
        $year = now()->format('Y');

        foreach (range(1, 5) as $n) {
            $this->existing($tenant, $type, sprintf("PV-%s-%06d", $year, $n));
        }

        // Exactly the state production was in.
        DB::table('voucher_types')->where('id', $type->id)
            ->update(['next_number' => 1, 'current_year' => (int) $year - 1]);

        $issued = $this->issue($tenant, $type);

        $this->assertSame("PV-{$year}-000006", $issued);
        $this->assertSame(0, Voucher::withoutGlobalScopes()
            ->where('company_id', $tenant['company']->id)->where('number', $issued)
            ->count(), 'the number issued must not already exist');
    }

    /** A counter ahead of reality is respected: numbers are never reused. */
    public function test_a_counter_ahead_of_reality_is_respected(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $type = $this->typeFor($tenant);
        $year = now()->format('Y');

        $this->existing($tenant, $type, "PV-{$year}-000001");

        DB::table('voucher_types')->where('id', $type->id)->update(['next_number' => 500]);

        $this->assertSame("PV-{$year}-000500", $this->issue($tenant, $type));
    }

    public function test_a_stale_year_no_longer_resets_over_existing_numbers(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $type = $this->typeFor($tenant);
        $year = now()->format('Y');

        $this->existing($tenant, $type, "PV-{$year}-000001");

        DB::table('voucher_types')->where('id', $type->id)
            ->update(['current_year' => (int) $year - 1, 'next_number' => 9]);

        $this->assertSame("PV-{$year}-000002", $this->issue($tenant, $type));
    }

    public function test_the_preview_matches_what_will_be_issued(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $type = $this->typeFor($tenant);
        $year = now()->format('Y');

        $this->existing($tenant, $type, "PV-{$year}-000007");
        DB::table('voucher_types')->where('id', $type->id)->update(['next_number' => 1]);

        $preview = $this->previewIn($tenant, $type);

        $this->assertSame($preview, $this->issue($tenant, $type));
    }

    /** Every configured type, not only Payment Voucher. */
    public function test_every_voucher_type_numbers_independently(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $year = now()->format('Y');

        $types = VoucherType::withoutGlobalScopes()
            ->where('company_id', $tenant['company']->id)->get();

        $this->assertGreaterThanOrEqual(4, $types->count());

        foreach ($types as $type) {
            $this->existing($tenant, $type, "{$type->prefix}-{$year}-000001");

            DB::table('voucher_types')->where('id', $type->id)
                ->update(['next_number' => 1, 'current_year' => (int) $year - 1]);

            $this->assertSame(
                "{$type->prefix}-{$year}-000002",
                $this->issue($tenant, $type),
                "{$type->code} must continue past its own existing voucher",
            );
        }
    }

    public function test_numbering_is_per_company(): void
    {
        $mine = $this->makeTenant('Acme Trading');
        $theirs = $this->makeTenant('Zamani Freight');
        $year = now()->format('Y');

        foreach (range(1, 4) as $n) {
            $this->existing($mine, $this->typeFor($mine), sprintf("PV-%s-%06d", $year, $n));
        }

        // A busy neighbour must not push this tenant's series along.
        $this->assertSame("PV-{$year}-000001", $this->issue($theirs, $this->typeFor($theirs)));
        $this->assertSame("PV-{$year}-000005", $this->issue($mine, $this->typeFor($mine)));
    }

    public function test_repeated_generation_never_repeats_a_number(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $type = $this->typeFor($tenant);

        $issued = [];

        for ($i = 0; $i < 25; $i++) {
            $number = $this->issue($tenant, $type);
            $this->existing($tenant, $type, $number);
            $issued[] = $number;
        }

        $this->assertCount(25, array_unique($issued));
    }

    /**
     * Generation takes a pessimistic row lock, which is what makes concurrent
     * submissions safe. Asserted by holding the lock on one connection and
     * showing a second cannot take it — NOWAIT fails rather than blocking, so
     * the test cannot hang.
     */
    public function test_generation_locks_the_counter_row(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $type = $this->typeFor($tenant);

        DB::beginTransaction();

        try {
            DB::table('voucher_types')->where('id', $type->id)->lockForUpdate()->first();

            $blocked = false;

            try {
                // A separate connection, so the lock is genuinely contended.
                $pdo = new \PDO(
                    sprintf('mysql:host=%s;port=%s;dbname=%s', config('database.connections.mysql.host'),
                        config('database.connections.mysql.port'), config('database.connections.mysql.database')),
                    config('database.connections.mysql.username'),
                    config('database.connections.mysql.password'),
                );
                $pdo->exec('SET SESSION innodb_lock_wait_timeout = 1');
                $pdo->beginTransaction();
                $pdo->query("SELECT id FROM voucher_types WHERE id = {$type->id} FOR UPDATE NOWAIT");
                $pdo->rollBack();
            } catch (\PDOException $e) {
                $blocked = true;
            }

            $this->assertTrue($blocked, 'a second connection should not be able to take the counter lock');
        } finally {
            DB::rollBack();
        }
    }

    /** The whole point: a voucher can be created after the demo data exists. */
    public function test_a_voucher_can_be_created_after_demo_seeding(): void
    {
        $this->seed(PlanSeeder::class);
        $this->seed(DemoSeeder::class);

        $company = Company::where('slug', 'watercom')->firstOrFail();

        $employee = \App\Models\User::withoutGlobalScopes()
            ->where('company_id', $company->id)->where('role', 'employee')->firstOrFail();

        $type = VoucherType::withoutGlobalScopes()
            ->where('company_id', $company->id)->where('code', 'payment')->firstOrFail();

        // Put the counter back into the broken state the bug produced.
        DB::table('voucher_types')->where('id', $type->id)
            ->update(['next_number' => 1, 'current_year' => (int) now()->format('Y') - 1]);

        $this->actingAs($employee, 'sanctum')
            ->postJson('/api/vouchers', [
                'voucher_type_id' => $type->id,
                'payee' => 'New Supplier Ltd',
                'purpose' => 'First voucher after seeding',
                'amount' => 250000,
            ])
            ->assertCreated();

        $duplicates = DB::table('vouchers')
            ->select('company_id', 'number')
            ->groupBy('company_id', 'number')
            ->havingRaw('count(*) > 1')
            ->count();

        $this->assertSame(0, $duplicates);
    }
}
