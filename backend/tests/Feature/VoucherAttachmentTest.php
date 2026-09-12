<?php

namespace Tests\Feature;

use App\Models\VoucherAttachment;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Supporting documents on a voucher.
 *
 * The endpoint existed and worked, but had no tests: a build running on the
 * in-browser fixture answered `Unknown action "attachments"` and it was not
 * obvious from here whether the gap was the client's or the server's. These
 * pin the server's half of the contract — what it accepts, what it refuses,
 * and that a file cannot cross a company boundary in either direction.
 */
class VoucherAttachmentTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    protected function setUp(): void
    {
        parent::setUp();

        // Attachments go on the private disk, never the public one.
        Storage::fake('local');
    }

    public function test_an_employee_can_attach_documents_to_their_draft(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $response = $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [
                    UploadedFile::fake()->create('invoice.pdf', 120, 'application/pdf'),
                    UploadedFile::fake()->image('receipt.jpg'),
                ],
            ]);

        $response->assertCreated()->assertJsonCount(2, 'data');

        $this->assertSame(2, VoucherAttachment::withoutGlobalScopes()
            ->where('voucher_id', $voucher->id)->count());
    }

    /** Every row must carry the tenant, or the global scope cannot hold it. */
    public function test_an_attachment_is_stamped_with_the_voucher_company(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('invoice.pdf', 10, 'application/pdf')],
            ])->assertCreated();

        $attachment = VoucherAttachment::withoutGlobalScopes()->firstOrFail();

        $this->assertSame($voucher->company_id, $attachment->company_id);
        $this->assertSame($tenant['employee']->id, $attachment->uploaded_by);
        $this->assertStringContainsString("companies/{$voucher->company_id}/", $attachment->path);
    }

    public function test_an_executable_is_refused(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('payload.exe', 12, 'application/x-msdownload')],
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('files.0');

        $this->assertSame(0, VoucherAttachment::withoutGlobalScopes()->count());
    }

    public function test_a_file_over_the_limit_is_refused(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $overLimit = ((int) config('vouchflow.max_upload_mb') * 1024) + 512;

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('huge.pdf', $overLimit, 'application/pdf')],
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('files.0');
    }

    public function test_another_company_cannot_attach_to_this_voucher(): void
    {
        $mine = $this->makeTenant('Acme Trading');
        $theirs = $this->makeTenant('Zamani Freight');

        $voucher = $this->makeVoucher($mine);

        $this->actingAs($theirs['admin'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('invoice.pdf', 10, 'application/pdf')],
            ])
            ->assertNotFound();

        $this->assertSame(0, VoucherAttachment::withoutGlobalScopes()->count());
    }

    public function test_another_company_cannot_download_this_attachment(): void
    {
        $mine = $this->makeTenant('Acme Trading');
        $theirs = $this->makeTenant('Zamani Freight');

        $voucher = $this->makeVoucher($mine);

        $this->actingAs($mine['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('invoice.pdf', 10, 'application/pdf')],
            ])->assertCreated();

        $attachment = VoucherAttachment::withoutGlobalScopes()->firstOrFail();

        $this->actingAs($theirs['admin'], 'sanctum')
            ->get("/api/vouchers/{$voucher->id}/attachments/{$attachment->id}")
            ->assertNotFound();
    }

    public function test_the_owner_can_download_their_attachment(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('invoice.pdf', 10, 'application/pdf')],
            ])->assertCreated();

        $attachment = VoucherAttachment::withoutGlobalScopes()->firstOrFail();

        $this->actingAs($tenant['employee'], 'sanctum')
            ->get("/api/vouchers/{$voucher->id}/attachments/{$attachment->id}")
            ->assertOk();
    }

    public function test_an_unauthenticated_request_is_rejected(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $this->postJson("/api/vouchers/{$voucher->id}/attachments", [
            'files' => [UploadedFile::fake()->create('invoice.pdf', 10, 'application/pdf')],
        ])->assertUnauthorized();
    }

    public function test_an_upload_with_no_files_is_refused(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [])
            ->assertStatus(422)
            ->assertJsonValidationErrors('files');
    }
}
