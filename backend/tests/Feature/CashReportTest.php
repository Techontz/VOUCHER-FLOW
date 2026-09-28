<?php

namespace Tests\Feature;

use App\Exports\TabularExport;
use App\Models\Department;
use App\Models\Voucher;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Maatwebsite\Excel\Facades\Excel;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * The cash report answers one question — "what cash moved, and what is still
 * owed, in this period?" — and must return exactly the rows the filters name,
 * on screen and in every export.
 */
class CashReportTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    /** @return array{0: array, 1: array<string, Voucher>} */
    private function ledger(): array
    {
        $t = $this->makeTenant('Cash Co');

        $other = app(TenantContext::class)->forCompany($t['company'], fn () => Department::create([
            'company_id' => $t['company']->id, 'name' => 'Stores', 'code' => 'STR',
        ]));

        $make = function (array $attributes) use ($t) {
            $voucher = $this->makeVoucher($t);
            $voucher->forceFill($attributes)->save();

            return $voucher->fresh();
        };

        $vouchers = [
            // Raised in August, paid in September: a September payment.
            'paidSept' => $make(['kind' => 'cash', 'status' => Voucher::STATUS_PAID, 'voucher_date' => '2026-08-28', 'payment_date' => '2026-09-03', 'paid_at' => '2026-09-03 10:00:00', 'amount' => 40000]),
            'paidSeptOther' => $make(['kind' => 'cash', 'status' => Voucher::STATUS_PAID, 'voucher_date' => '2026-09-10', 'payment_date' => '2026-09-12', 'paid_at' => '2026-09-12 10:00:00', 'amount' => 15000, 'department_id' => $other->id]),
            // Raised in September, not yet paid: outstanding in September.
            'owedSept' => $make(['kind' => 'cash', 'status' => Voucher::STATUS_APPROVED, 'voucher_date' => '2026-09-18', 'amount' => 70000]),
            // Raised in September, paid in October: an October payment.
            'paidOct' => $make(['kind' => 'cash', 'status' => Voucher::STATUS_PAID, 'voucher_date' => '2026-09-25', 'payment_date' => '2026-10-02', 'paid_at' => '2026-10-02 10:00:00', 'amount' => 9000]),
            'paidAug' => $make(['kind' => 'cash', 'status' => Voucher::STATUS_PAID, 'voucher_date' => '2026-08-01', 'payment_date' => '2026-08-05', 'paid_at' => '2026-08-05 10:00:00', 'amount' => 5000]),
            // Not cash, or not yet approved: never in a cash report.
            'bankSept' => $make(['kind' => 'bank', 'status' => Voucher::STATUS_PAID, 'voucher_date' => '2026-09-05', 'payment_date' => '2026-09-06', 'paid_at' => '2026-09-06 10:00:00']),
            'pendingSept' => $make(['kind' => 'cash', 'status' => Voucher::STATUS_IN_REVIEW, 'voucher_date' => '2026-09-07', 'current_step_position' => 1]),
        ];

        return [$t + ['other' => $other], $vouchers];
    }

    private function sorted(Voucher ...$vouchers): array
    {
        return collect($vouchers)->pluck('number')->sort()->values()->all();
    }

    private function rowNumbers(array $rows): array
    {
        return collect($rows)->pluck(0)->sort()->values()->all();
    }

    public function test_the_cash_report_is_offered_to_the_roles_that_see_payments(): void
    {
        $t = $this->makeTenant('Cash Co');

        $keys = fn ($user) => array_column($this->actingAs($user, 'sanctum')->getJson('/api/reports')->json('data'), 'key');

        $this->assertContains('cash', $keys($t['cashier']));
        $this->assertContains('cash', $keys($t['finance']));
        $this->assertContains('cash', $keys($t['admin']));
        $this->assertNotContains('cash', $keys($t['employee']));
    }

    public function test_a_september_cash_report_returns_only_september_cash_records(): void
    {
        [$t, $v] = $this->ledger();

        $response = $this->actingAs($t['cashier'], 'sanctum')
            ->getJson('/api/reports/cash?from=2026-09-01&to=2026-09-30')
            ->assertOk();

        $this->assertSame(
            $this->sorted($v['paidSept'], $v['paidSeptOther'], $v['owedSept']),
            $this->rowNumbers($response->json('rows')),
        );

        $this->assertSame(2, $response->json('summary.paid_count'));
        $this->assertEquals(55000, $response->json('summary.paid_total'));
        $this->assertSame(1, $response->json('summary.outstanding_count'));
        $this->assertSame(2, $response->json('summary.cash_count'));
        $this->assertSame(0, $response->json('summary.bank_count'));
    }

    public function test_status_and_department_filters_narrow_the_cash_report(): void
    {
        [$t, $v] = $this->ledger();

        $paid = $this->actingAs($t['cashier'], 'sanctum')
            ->getJson('/api/reports/cash?from=2026-09-01&to=2026-09-30&status=paid')->assertOk();
        $this->assertSame($this->sorted($v['paidSept'], $v['paidSeptOther']), $this->rowNumbers($paid->json('rows')));

        $owed = $this->actingAs($t['cashier'], 'sanctum')
            ->getJson('/api/reports/cash?status=awaiting_payment')->assertOk();
        $this->assertSame($this->sorted($v['owedSept']), $this->rowNumbers($owed->json('rows')));

        $department = $this->actingAs($t['cashier'], 'sanctum')
            ->getJson('/api/reports/cash?from=2026-09-01&to=2026-09-30&department_id='.$t['other']->id)->assertOk();
        $this->assertSame($this->sorted($v['paidSeptOther']), $this->rowNumbers($department->json('rows')));

        $this->actingAs($t['cashier'], 'sanctum')->getJson('/api/reports/cash?status=bogus')->assertUnprocessable();
    }

    public function test_the_payment_report_dates_paid_rows_by_payment_date(): void
    {
        [$t, $v] = $this->ledger();

        $rows = $this->actingAs($t['cashier'], 'sanctum')
            ->getJson('/api/reports/payments?from=2026-09-01&to=2026-09-30')->assertOk()->json('rows');

        $this->assertSame(
            $this->sorted($v['paidSept'], $v['paidSeptOther'], $v['owedSept'], $v['bankSept']),
            $this->rowNumbers($rows),
        );
    }

    public function test_a_csv_export_contains_exactly_the_filtered_rows(): void
    {
        [$t, $v] = $this->ledger();

        $response = $this->actingAs($t['cashier'], 'sanctum')
            ->get('/api/reports/cash/export?format=csv&from=2026-09-01&to=2026-09-30&status=paid')
            ->assertOk();

        $lines = array_values(array_filter(explode("\n", trim(str_replace("\xEF\xBB\xBF", '', $response->streamedContent())))));
        $body = array_map('str_getcsv', array_slice($lines, 1));

        $this->assertSame('Number', str_getcsv($lines[0])[0]);
        $this->assertSame($this->sorted($v['paidSept'], $v['paidSeptOther']), $this->rowNumbers($body));
    }

    public function test_an_excel_export_contains_exactly_the_filtered_rows(): void
    {
        [$t, $v] = $this->ledger();

        Excel::fake();
        $this->travelTo(now()->setDateTime(2026, 9, 30, 12, 0, 0));

        $this->actingAs($t['cashier'], 'sanctum')
            ->get('/api/reports/cash/export?format=xlsx&from=2026-09-01&to=2026-09-30')
            ->assertOk();

        Excel::assertDownloaded('vouchflow-cash-20260930-120000.xlsx', function (TabularExport $export) use ($v) {
            return $this->rowNumbers($export->array()) === $this->sorted($v['paidSept'], $v['paidSeptOther'], $v['owedSept']);
        });
    }

    public function test_the_voucher_report_export_honours_search_and_status(): void
    {
        [$t, $v] = $this->ledger();
        $v['owedSept']->forceFill(['payee' => 'Kilimanjaro Hardware'])->save();

        $response = $this->actingAs($t['admin'], 'sanctum')
            ->get('/api/reports/vouchers/export?format=csv&q=Kilimanjaro&status=awaiting_payment')
            ->assertOk();

        $lines = array_values(array_filter(explode("\n", trim(str_replace("\xEF\xBB\xBF", '', $response->streamedContent())))));
        $this->assertSame([$v['owedSept']->number], $this->rowNumbers(array_map('str_getcsv', array_slice($lines, 1))));
    }

    public function test_an_employee_cannot_run_the_cash_report(): void
    {
        [$t] = $this->ledger();

        $this->actingAs($t['employee'], 'sanctum')->getJson('/api/reports/cash')->assertForbidden();
        $this->actingAs($t['employee'], 'sanctum')->get('/api/reports/cash/export?format=csv')->assertForbidden();
    }

    public function test_another_companys_cash_never_appears(): void
    {
        [$t, $v] = $this->ledger();

        $b = $this->makeTenant('Other Co');
        $foreign = $this->makeVoucher($b);
        $foreign->forceFill(['number' => 'PV-FOREIGN-0001', 'kind' => 'cash', 'status' => Voucher::STATUS_PAID, 'voucher_date' => '2026-09-10', 'payment_date' => '2026-09-11'])->save();

        $rows = $this->actingAs($t['cashier'], 'sanctum')
            ->getJson('/api/reports/cash?from=2026-09-01&to=2026-09-30')->assertOk()->json('rows');

        $this->assertNotContains($foreign->number, array_column($rows, 0));

        $theirs = $this->actingAs($b['cashier'], 'sanctum')
            ->getJson('/api/reports/cash?from=2026-09-01&to=2026-09-30')->assertOk()->json('rows');

        $this->assertSame([$foreign->number], array_column($theirs, 0));
    }
}
