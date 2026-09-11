<?php

namespace Tests\Feature;

use App\Models\Voucher;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * A dashboard is an action queue, not a history page.
 *
 * The rule these tests hold down: completing your step REMOVES the voucher from
 * your dashboard and puts it on whoever is next. A queue that keeps finished
 * work stops telling anyone what to do.
 */
class ActionQueueTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    private const SIGNATURE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    /** @return array<string,int> */
    private function queues(array $t): array
    {
        $count = fn ($user) => count(
            $this->actingAs($user, 'sanctum')->getJson('/api/dashboard')->json('data.queue') ?? []
        );

        return [
            'employee' => $count($t['employee']),
            'hod' => $count($t['hod']),
            'ceo' => $count($t['ceo']),
            'cashier' => $count($t['cashier']),
        ];
    }

    public function test_a_voucher_moves_from_one_queue_to_the_next_and_leaves_the_last(): void
    {
        $t = $this->makeTenant('Watercom Demo');
        $voucher = $this->makeVoucher($t);

        $this->assertSame(
            ['employee' => 1, 'hod' => 0, 'ceo' => 0, 'cashier' => 0],
            $this->queues($t),
            'A draft sits with its author and nobody else.',
        );

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit")->assertOk();
        $this->assertSame(
            ['employee' => 0, 'hod' => 1, 'ceo' => 0, 'cashier' => 0],
            $this->queues($t),
            'Submitting hands it to the HOD and clears the author.',
        );

        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE])->assertOk();
        $this->assertSame(1, $this->queues($t)['hod'], 'Signing alone does not hand it on — submitting does.');

        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed")->assertOk();
        $this->assertSame(
            ['employee' => 0, 'hod' => 0, 'ceo' => 1, 'cashier' => 0],
            $this->queues($t),
        );

        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve")->assertOk();
        $this->assertSame(
            ['employee' => 0, 'hod' => 0, 'ceo' => 0, 'cashier' => 1],
            $this->queues($t),
            'Approval is not completion — the money still has to move.',
        );

        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['payment_reference' => 'TRX-1'])->assertOk();

        $this->assertSame(
            ['employee' => 0, 'hod' => 0, 'ceo' => 0, 'cashier' => 0],
            $this->queues($t),
            'A paid voucher belongs to Reports, not to anybody\'s dashboard.',
        );
    }

    public function test_a_paid_voucher_is_still_found_through_reports(): void
    {
        $t = $this->makeTenant('Watercom Demo');
        $voucher = $this->makeVoucher($t);

        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit");
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/sign", ['signature' => self::SIGNATURE]);
        $this->actingAs($t['hod'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/submit-signed");
        $this->actingAs($t['ceo'], 'sanctum')->postJson("/api/vouchers/{$voucher->id}/approve");
        $this->actingAs($t['cashier'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/pay", ['payment_reference' => 'TRX-77']);

        $rows = $this->actingAs($t['cashier'], 'sanctum')
            ->getJson('/api/reports/payments')->assertOk()->json('rows');

        $this->assertContains($voucher->fresh()->number, array_column($rows, 0));

        // And its author can still find it in their own report.
        $mine = $this->actingAs($t['employee'], 'sanctum')
            ->getJson('/api/reports/vouchers')->assertOk()->json('rows');

        $this->assertContains($voucher->fresh()->number, array_column($mine, 0));
    }

    public function test_an_administrators_queue_is_what_has_stalled_not_everything(): void
    {
        $t = $this->makeTenant('Watercom Demo');

        $moving = $this->makeVoucher($t);
        $this->actingAs($t['employee'], 'sanctum')->postJson("/api/vouchers/{$moving->id}/submit");

        $this->assertCount(
            0,
            $this->actingAs($t['admin'], 'sanctum')->getJson('/api/dashboard')->assertOk()->json('data.queue'),
            'A voucher moving normally is not an administrator\'s problem.',
        );

        // Same voucher, untouched for a week.
        $moving->fresh()->forceFill([
            'updated_at' => now()->subDays(7),
            'submitted_at' => now()->subDays(7),
        ])->saveQuietly();

        $this->assertCount(
            1,
            $this->actingAs($t['admin'], 'sanctum')->getJson('/api/dashboard')->json('data.queue'),
        );
    }
}
