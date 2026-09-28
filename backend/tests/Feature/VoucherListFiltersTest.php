<?php

namespace Tests\Feature;

use App\Models\Department;
use App\Models\Voucher;
use App\Models\VoucherApproval;
use App\Models\VoucherType;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Every control on the voucher register must actually narrow the list. A filter
 * the server ignores is worse than no filter: it quietly shows the wrong rows.
 */
class VoucherListFiltersTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    /** @return array{0: array, 1: array<string, Voucher>} */
    private function register(): array
    {
        $t = $this->makeTenant('Filter Co');

        $other = app(TenantContext::class)->forCompany($t['company'], fn () => Department::create([
            'company_id' => $t['company']->id, 'name' => 'Logistics', 'code' => 'LOG',
        ]));
        $pettyCash = app(TenantContext::class)->forCompany($t['company'], fn () => VoucherType::where('code', 'petty_cash')->firstOrFail());

        $make = function (array $attributes) use ($t) {
            $voucher = $this->makeVoucher($t);
            $voucher->forceFill($attributes)->save();

            return $voucher->fresh();
        };

        $vouchers = [
            'bankPending' => $make(['kind' => 'bank', 'status' => Voucher::STATUS_IN_REVIEW, 'current_step_position' => 1, 'voucher_date' => '2026-09-05', 'payee' => 'Alpha Traders', 'submitted_at' => now()]),
            'cashPaid' => $make(['kind' => 'cash', 'status' => Voucher::STATUS_PAID, 'voucher_date' => '2026-08-10', 'payment_date' => '2026-09-14', 'paid_at' => now(), 'payee' => 'Beta Stores']),
            'bankApproved' => $make(['kind' => 'bank', 'status' => Voucher::STATUS_APPROVED, 'voucher_date' => '2026-09-20', 'payee' => 'Gamma Ltd', 'department_id' => $other->id]),
            'draft' => $make(['kind' => 'cash', 'status' => Voucher::STATUS_DRAFT, 'voucher_date' => '2026-09-21', 'payee' => 'Delta Co', 'voucher_type_id' => $pettyCash->id]),
            'rejected' => $make(['kind' => 'bank', 'status' => Voucher::STATUS_REJECTED, 'voucher_date' => '2026-07-01', 'payee' => 'Epsilon', 'rejected_at' => now()]),
            'changes' => $make(['kind' => 'bank', 'status' => Voucher::STATUS_CHANGES_REQUESTED, 'voucher_date' => '2026-09-02', 'payee' => 'Zeta']),
        ];

        return [$t + ['other' => $other, 'petty' => $pettyCash], $vouchers];
    }

    private function numbers(array $t, string $query): array
    {
        return collect($this->actingAs($t['admin'], 'sanctum')->getJson('/api/vouchers?per_page=100&'.$query)
            ->assertOk()->json('data'))->pluck('number')->sort()->values()->all();
    }

    private function numbersOf(Voucher ...$vouchers): array
    {
        return collect($vouchers)->pluck('number')->sort()->values()->all();
    }

    public function test_the_bank_or_cash_filter_is_applied(): void
    {
        [$t, $v] = $this->register();

        $this->assertSame($this->numbersOf($v['cashPaid'], $v['draft']), $this->numbers($t, 'kind=cash'));
        $this->assertSame(
            $this->numbersOf($v['bankPending'], $v['bankApproved'], $v['rejected'], $v['changes']),
            $this->numbers($t, 'kind=bank'),
        );

        $this->actingAs($t['admin'], 'sanctum')->getJson('/api/vouchers?kind=cheque')->assertUnprocessable();
    }

    public function test_every_status_tab_returns_only_its_own_vouchers(): void
    {
        [$t, $v] = $this->register();

        $this->assertSame($this->numbersOf($v['bankPending']), $this->numbers($t, 'status=pending'));
        $this->assertSame($this->numbersOf($v['draft']), $this->numbers($t, 'status=drafts'));
        $this->assertSame($this->numbersOf($v['bankApproved']), $this->numbers($t, 'status=approved'));
        $this->assertSame($this->numbersOf($v['bankApproved']), $this->numbers($t, 'status=awaiting_payment'));
        $this->assertSame($this->numbersOf($v['cashPaid']), $this->numbers($t, 'status=paid'));
        $this->assertSame($this->numbersOf($v['rejected']), $this->numbers($t, 'status=rejected'));
        $this->assertSame($this->numbersOf($v['changes']), $this->numbers($t, 'status=changes_requested'));
        $this->assertCount(6, $this->numbers($t, ''));
    }

    public function test_search_department_type_and_date_filters_narrow_the_list(): void
    {
        [$t, $v] = $this->register();

        $this->assertSame($this->numbersOf($v['bankPending']), $this->numbers($t, 'q=Alpha'));
        $this->assertSame($this->numbersOf($v['bankApproved']), $this->numbers($t, 'department_id='.$t['other']->id));
        $this->assertSame($this->numbersOf($v['draft']), $this->numbers($t, 'voucher_type_id='.$t['petty']->id));
        $this->assertSame(
            $this->numbersOf($v['bankPending'], $v['bankApproved'], $v['draft'], $v['changes']),
            $this->numbers($t, 'from=2026-09-01&to=2026-09-30'),
        );
        $this->assertSame($this->numbersOf($v['rejected']), $this->numbers($t, 'to=2026-07-31'));

        // Combined filters intersect.
        $this->assertSame($this->numbersOf($v['bankApproved']), $this->numbers($t, 'kind=bank&from=2026-09-10'));
    }

    public function test_paid_date_filter_and_total_amount_follow_the_filters(): void
    {
        [$t, $v] = $this->register();

        $response = $this->actingAs($t['admin'], 'sanctum')
            ->getJson('/api/vouchers?status=paid&paid_from=2026-09-01&paid_to=2026-09-30')->assertOk();

        $this->assertSame([$v['cashPaid']->number], $response->json('data.*.number'));
        $this->assertEquals((float) $v['cashPaid']->amount, $response->json('meta.total_amount'));

        $this->assertSame([], $this->numbers($t, 'status=paid&paid_from=2026-10-01'));
    }

    public function test_a_list_row_names_who_refused_the_voucher(): void
    {
        [$t, $v] = $this->register();

        app(TenantContext::class)->forCompany($t['company'], fn () => VoucherApproval::create([
            'company_id' => $t['company']->id,
            'voucher_id' => $v['rejected']->id,
            'step_position' => 1,
            'actor_id' => $t['hod']->id,
            'actor_name' => 'Emmanuel Massawe',
            'action' => 'rejected',
            'acted_at' => now(),
        ]));

        $rows = collect($this->actingAs($t['admin'], 'sanctum')->getJson('/api/vouchers?status=rejected')->assertOk()->json('data'));

        $this->assertSame('Emmanuel Massawe', $rows->firstWhere('number', $v['rejected']->number)['decided_by']);
    }

    public function test_an_employee_filters_only_ever_their_own_vouchers(): void
    {
        [$t, $v] = $this->register();

        // Someone else's cash voucher in the same company.
        $colleagueVoucher = $this->makeVoucher($t, $t['hod']);
        $colleagueVoucher->forceFill(['kind' => 'cash', 'status' => Voucher::STATUS_PAID])->save();

        $numbers = collect($this->actingAs($t['employee'], 'sanctum')->getJson('/api/vouchers?kind=cash')->assertOk()->json('data'))
            ->pluck('number')->all();

        $this->assertContains($v['cashPaid']->number, $numbers);
        $this->assertNotContains($colleagueVoucher->number, $numbers);
    }
}
