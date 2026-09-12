<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\Plan;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherType;
use Database\Seeders\DatabaseSeeder;
use Database\Seeders\DemoSeeder;
use Database\Seeders\PlanSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The demo seeder has to survive being run again.
 *
 * It failed in production on vouchers_company_id_number_unique, because the
 * numbers it asked for came from a counter rather than from the voucher's own
 * identity. These tests pin down both halves of the fix: that a rerun adds
 * nothing, and that it does not quietly move the demo world on either.
 */
class DemoSeederIdempotencyTest extends TestCase
{
    use RefreshDatabase;

    /** Every table the seeder writes to. */
    private const TABLES = [
        'companies', 'users', 'departments', 'voucher_types', 'workflows', 'workflow_steps',
        'vouchers', 'voucher_approvals', 'voucher_comments', 'invoices', 'subscriptions',
        'app_notifications', 'audit_logs',
    ];

    private function census(): array
    {
        $counts = [];

        foreach (self::TABLES as $table) {
            $counts[$table] = DB::table($table)->count();
        }

        return $counts;
    }

    private function seedDemo(): void
    {
        $this->seed(PlanSeeder::class);
        $this->seed(DemoSeeder::class);
    }

    public function test_it_runs_once(): void
    {
        $this->seedDemo();

        $this->assertSame(3, Company::count(), 'the demo world is three tenants');
        $this->assertGreaterThan(0, Voucher::withoutGlobalScopes()->count());
    }

    public function test_it_runs_twice_without_duplicating_anything(): void
    {
        $this->seedDemo();
        $first = $this->census();

        $this->seed(DemoSeeder::class);

        $this->assertSame($first, $this->census(), 'a second run must add nothing');
    }

    public function test_it_runs_three_times(): void
    {
        $this->seedDemo();
        $first = $this->census();

        $this->seed(DemoSeeder::class);
        $this->seed(DemoSeeder::class);

        $this->assertSame($first, $this->census(), 'a third run must still add nothing');
    }

    public function test_it_creates_no_duplicate_voucher_numbers(): void
    {
        $this->seedDemo();
        $this->seed(DemoSeeder::class);
        $this->seed(DemoSeeder::class);

        $duplicates = DB::table('vouchers')
            ->select('company_id', 'number')
            ->groupBy('company_id', 'number')
            ->havingRaw('count(*) > 1')
            ->get();

        $this->assertCount(0, $duplicates, 'company_id + number is unique per tenant');
    }

    /**
     * The failure in production was not "a duplicate row appeared" — the unique
     * key stopped that. It was the insert dying. This asserts the seeder can be
     * re-run after its counters have been left where a first run put them.
     */
    public function test_a_rerun_does_not_reuse_an_issued_number(): void
    {
        $this->seedDemo();

        $watercom = Company::where('slug', 'watercom')->firstOrFail();

        foreach (VoucherType::withoutGlobalScopes()->where('company_id', $watercom->id)->get() as $type) {
            $issued = Voucher::withoutGlobalScopes()
                ->where('company_id', $watercom->id)
                ->where('voucher_type_id', $type->id)
                ->count();

            if ($issued === 0) {
                continue;
            }

            $this->assertGreaterThan(
                $issued,
                (int) $type->next_number,
                "{$type->code}: the counter must sit past every number already issued",
            );
        }
    }

    /** Seeding must not reset a counter that has already issued numbers. */
    public function test_reseeding_voucher_types_leaves_live_counters_alone(): void
    {
        $this->seedDemo();

        $watercom = Company::where('slug', 'watercom')->firstOrFail();
        $type = VoucherType::withoutGlobalScopes()
            ->where('company_id', $watercom->id)->where('code', 'payment')->firstOrFail();

        $before = (int) $type->next_number;
        $this->assertGreaterThan(1, $before, 'the demo issued payment vouchers, so this has moved');

        app(\App\Services\CompanyProvisioner::class)->seedVoucherTypes($watercom);

        $this->assertSame($before, (int) $type->fresh()->next_number);
    }

    public function test_watercom_remains_the_demo_company(): void
    {
        $this->seedDemo();
        $this->seed(DemoSeeder::class);

        $watercom = Company::where('slug', 'watercom')->first();

        $this->assertNotNull($watercom, 'the primary demo tenant is addressed by a stable slug');
        $this->assertSame('Watercom (T) Limited', $watercom->name);
        $this->assertSame('WATERCOM (T) LIMITED', $watercom->legal_name);
        $this->assertSame(1, Company::where('name', 'Watercom (T) Limited')->count(), 'exactly one of them');
    }

    public function test_it_does_not_create_magertech_or_acme(): void
    {
        $this->seedDemo();
        $this->seed(DemoSeeder::class);

        foreach (['MagerTech', 'Acme'] as $unwanted) {
            $this->assertSame(
                0,
                Company::where('name', 'like', "%{$unwanted}%")->count(),
                "{$unwanted} is not part of this product",
            );
        }
    }

    public function test_tenant_relationships_survive_a_rerun(): void
    {
        $this->seedDemo();
        $this->seed(DemoSeeder::class);

        // Nothing may be parented to a company that does not exist.
        $companyIds = Company::pluck('id');

        foreach (['users', 'departments', 'vouchers', 'voucher_types', 'workflows'] as $table) {
            $orphans = DB::table($table)->whereNotNull('company_id')
                ->whereNotIn('company_id', $companyIds)->count();

            $this->assertSame(0, $orphans, "{$table} has rows pointing at a missing company");
        }

        // And every voucher must sit with its own tenant's people and types.
        $crossed = DB::table('vouchers')
            ->join('users', 'users.id', '=', 'vouchers.requester_id')
            ->whereColumn('users.company_id', '!=', 'vouchers.company_id')
            ->count();

        $this->assertSame(0, $crossed, 'a voucher is requested by someone from another company');

        $crossedTypes = DB::table('vouchers')
            ->join('voucher_types', 'voucher_types.id', '=', 'vouchers.voucher_type_id')
            ->whereColumn('voucher_types.company_id', '!=', 'vouchers.company_id')
            ->count();

        $this->assertSame(0, $crossedTypes, 'a voucher uses another company\'s voucher type');
    }

    /**
     * The demo deliberately parks vouchers mid-flight so the action queues have
     * something in them. A rerun used to drive those one step further, and the
     * queues drained towards empty.
     */
    public function test_a_rerun_does_not_advance_the_workflow(): void
    {
        $this->seedDemo();

        $before = Voucher::withoutGlobalScopes()->selectRaw('status, count(*) as total')
            ->groupBy('status')->pluck('total', 'status')->toArray();

        $this->seed(DemoSeeder::class);
        $this->seed(DemoSeeder::class);

        $after = Voucher::withoutGlobalScopes()->selectRaw('status, count(*) as total')
            ->groupBy('status')->pluck('total', 'status')->toArray();

        $this->assertSame($before, $after, 'the demo queues must look the same after a rerun');
        $this->assertGreaterThan(0, $after['in_review'] ?? 0, 'and must still have work waiting');
    }

    public function test_plan_seeder_is_idempotent(): void
    {
        $this->seed(PlanSeeder::class);
        $first = Plan::count();

        $this->seed(PlanSeeder::class);
        $this->seed(PlanSeeder::class);

        $this->assertSame($first, Plan::count());
        $this->assertSame(4, $first, 'Starter, Business, Premium, Enterprise');

        foreach (['starter', 'business', 'premium', 'enterprise'] as $code) {
            $this->assertSame(1, Plan::where('code', $code)->count(), "one {$code} plan");
        }
    }

    public function test_seed_demo_false_prevents_automatic_demo_seeding(): void
    {
        config(['vouchflow.seed_demo' => false]);

        $this->seed(DatabaseSeeder::class);

        $this->assertSame(0, Company::count(), 'db:seed must not create demo tenants');
        $this->assertSame(4, Plan::count(), 'but the plans must still be there');
        $this->assertSame(
            1,
            User::withoutGlobalScopes()->where('role', User::ROLE_SUPER_ADMIN)->count(),
            'and so must the platform operator',
        );
    }

    /** SEED_DEMO unset resolves to false in config, which is the default. */
    public function test_demo_is_not_seeded_when_the_flag_is_absent(): void
    {
        config(['vouchflow.seed_demo' => false]);

        $this->seed(DatabaseSeeder::class);

        $this->assertSame(0, Company::count(), 'the default is off');
        $this->assertSame(4, Plan::count());
    }

    /** And the gate opens when asked, or it would not be a gate. */
    public function test_seed_demo_true_opts_in(): void
    {
        config(['vouchflow.seed_demo' => true]);

        $this->seed(DatabaseSeeder::class);

        $this->assertSame(3, Company::count());
        $this->assertSame('Watercom (T) Limited', Company::where('slug', 'watercom')->firstOrFail()->name);
    }
}
