<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\Voucher;
use App\Models\VoucherAttachment;
use App\Models\VoucherType;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * A voucher you have just created is yours, and it is a draft.
 *
 * Saving a draft with a document attached failed with "Attachments can only be
 * added while the voucher is editable." Ownership was decided by
 *
 *     $voucher->requester_id === $user->id
 *
 * and MySQL returns integer columns as strings under emulated prepared
 * statements. Eloquent casts a model's own primary key to int but not a
 * foreign key, so this was "8" === 8 — false — and the author of a brand-new
 * draft was treated as a stranger to it.
 *
 * The behavioural tests below would pass either way on a connection that hands
 * back integers, which is exactly how this reached production. The cast tests
 * are the ones that hold the line.
 */
class DraftEditabilityTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('local');
    }

    private function typeFor(array $tenant): VoucherType
    {
        return VoucherType::withoutGlobalScopes()
            ->where('company_id', $tenant['company']->id)
            ->where('code', 'payment')
            ->firstOrFail();
    }

    /* ─────────────────────────────── the reported flow ─────────────────── */

    public function test_saving_a_draft_with_no_attachments_succeeds(): void
    {
        $tenant = $this->makeTenant('Acme Trading');

        $response = $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson('/api/vouchers', [
                'voucher_type_id' => $this->typeFor($tenant)->id,
                'payee' => 'Supplier Ltd',
                'purpose' => 'Stationery',
                'amount' => 50000,
            ]);

        $response->assertCreated()
            ->assertJsonPath('data.status', Voucher::STATUS_DRAFT)
            ->assertJsonPath('data.actions.edit', true);
    }

    /** The sequence the Create page performs: create, then upload. */
    public function test_saving_a_draft_with_attachments_succeeds(): void
    {
        $tenant = $this->makeTenant('Acme Trading');

        $id = $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson('/api/vouchers', [
                'voucher_type_id' => $this->typeFor($tenant)->id,
                'payee' => 'Supplier Ltd', 'purpose' => 'Stationery', 'amount' => 50000,
            ])->assertCreated()->json('data.id');

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$id}/attachments", [
                'files' => [UploadedFile::fake()->create('invoice.pdf', 20, 'application/pdf')],
            ])
            ->assertCreated();

        $this->assertSame(1, VoucherAttachment::withoutGlobalScopes()->where('voucher_id', $id)->count());
    }

    public function test_an_editable_draft_accepts_attachments(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $this->assertSame(Voucher::STATUS_DRAFT, $voucher->status);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('invoice.pdf', 20, 'application/pdf')],
            ])
            ->assertCreated();
    }

    /** Editability really does end at submission — the rule still bites. */
    public function test_attachments_are_refused_once_the_voucher_is_submitted(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/submit")
            ->assertOk();

        $this->assertNotSame(Voucher::STATUS_DRAFT, $voucher->fresh()->status);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('late.pdf', 20, 'application/pdf')],
            ])
            ->assertForbidden();
    }

    /* ───────────────────────── the actual defect: types ────────────────── */

    /**
     * A model hydrated from string attributes — which is what the driver hands
     * back in production — must still compare as an integer.
     */
    public function test_a_foreign_key_hydrated_as_a_string_is_cast_to_an_integer(): void
    {
        $voucher = new Voucher;
        $voucher->setRawAttributes([
            'id' => '1', 'company_id' => '2', 'requester_id' => '8', 'voucher_type_id' => '3',
        ], true);

        $this->assertSame(8, $voucher->requester_id);
        $this->assertSame(2, $voucher->company_id);
        $this->assertTrue($voucher->requester_id === 8, 'ownership is decided by a strict comparison');
    }

    /**
     * Every foreign key on every model is cast.
     *
     * Derived from the schema rather than a hand-written list, so a column
     * added later is covered without anyone remembering to come back here.
     * This is the test that would have caught the original defect.
     */
    public function test_every_foreign_key_is_cast_to_an_integer(): void
    {
        $models = [
            \App\Models\Voucher::class, \App\Models\VoucherAttachment::class,
            \App\Models\VoucherComment::class, \App\Models\VoucherApproval::class,
            \App\Models\VoucherType::class, \App\Models\AppNotification::class,
            \App\Models\User::class, \App\Models\Workflow::class,
            \App\Models\WorkflowStep::class, \App\Models\Department::class,
            \App\Models\Company::class, \App\Models\Invoice::class,
            \App\Models\Subscription::class, \App\Models\AuditLog::class,
        ];

        $missing = [];

        foreach ($models as $class) {
            /** @var \Illuminate\Database\Eloquent\Model $model */
            $model = new $class;
            $casts = $model->getCasts();

            foreach (Schema::getColumnListing($model->getTable()) as $column) {
                if (! str_ends_with($column, '_id') || $column === $model->getKeyName()) {
                    continue;
                }

                if (($casts[$column] ?? null) !== 'integer') {
                    $missing[] = class_basename($class).'.'.$column;
                }
            }
        }

        $this->assertSame([], $missing, 'these foreign keys would compare as strings: '.implode(', ', $missing));
    }

    /* ──────────── the same defect elsewhere, now also closed ───────────── */

    public function test_a_notification_can_be_marked_read_by_its_owner(): void
    {
        $tenant = $this->makeTenant('Acme Trading');

        $notification = AppNotification::create([
            'company_id' => $tenant['company']->id,
            'user_id' => $tenant['employee']->id,
            'type' => 'voucher.submitted', 'icon' => 'bell',
            'title' => 'A voucher needs you', 'body' => 'Test',
        ]);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/notifications/{$notification->id}/read")
            ->assertOk();

        $this->assertNotNull($notification->fresh()->read_at);
    }

    public function test_a_company_admin_can_update_their_own_company(): void
    {
        $tenant = $this->makeTenant('Acme Trading');

        $this->actingAs($tenant['admin'], 'sanctum')
            ->putJson('/api/company', ['phone' => '+255 700 000 000'])
            ->assertOk();

        $this->assertSame('+255 700 000 000', $tenant['company']->fresh()->phone);
    }

    public function test_an_attachment_can_be_downloaded_by_its_owner(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('invoice.pdf', 20, 'application/pdf')],
            ])->assertCreated();

        $attachment = VoucherAttachment::withoutGlobalScopes()->firstOrFail();

        // Matched by $attachment->voucher_id === $voucher->id, another pair
        // that was a string against an integer.
        $this->actingAs($tenant['employee'], 'sanctum')
            ->get("/api/vouchers/{$voucher->id}/attachments/{$attachment->id}")
            ->assertOk();
    }
}
