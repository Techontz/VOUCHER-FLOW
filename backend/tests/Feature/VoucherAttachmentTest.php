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

    /**
     * The three formats people actually attach, sent the way a browser sends
     * them — one multipart request, one files[] part each — must each arrive
     * as their own row and their own stored file, bytes intact.
     */
    public function test_pdf_jpg_and_png_in_one_request_are_each_stored(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $files = [
            UploadedFile::fake()->createWithContent('invoice.pdf', "%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n"),
            UploadedFile::fake()->image('delivery-note.jpg', 64, 48),
            UploadedFile::fake()->image('receipt-scan.png', 64, 48),
        ];
        $bytes = array_map(fn (UploadedFile $f) => file_get_contents($f->getRealPath()), $files);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->post("/api/vouchers/{$voucher->id}/attachments", ['files' => $files], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonCount(3, 'data')
            ->assertJsonPath('data.0.name', 'invoice.pdf')
            ->assertJsonPath('data.1.name', 'delivery-note.jpg')
            ->assertJsonPath('data.2.name', 'receipt-scan.png');

        $rows = VoucherAttachment::withoutGlobalScopes()->where('voucher_id', $voucher->id)->orderBy('id')->get();

        $this->assertSame(['application/pdf', 'image/jpeg', 'image/png'], $rows->pluck('mime_type')->all());

        foreach ($rows as $index => $row) {
            Storage::disk('local')->assertExists($row->path);
            $this->assertSame($bytes[$index], Storage::disk('local')->get($row->path), "{$row->original_name} was stored altered");
            $this->assertSame(strlen($bytes[$index]), (int) $row->size_bytes);
        }
    }

    /** What "it survives a refresh" means on the server: the voucher comes back with them. */
    public function test_uploaded_attachments_come_back_when_the_voucher_is_reloaded(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [
                    UploadedFile::fake()->create('invoice.pdf', 40, 'application/pdf'),
                    UploadedFile::fake()->image('receipt.png'),
                ],
            ])->assertCreated();

        $this->actingAs($tenant['employee'], 'sanctum')
            ->getJson("/api/vouchers/{$voucher->id}")
            ->assertOk()
            ->assertJsonCount(2, 'data.attachments')
            ->assertJsonPath('data.attachments.0.name', 'invoice.pdf')
            ->assertJsonPath('data.attachments.1.name', 'receipt.png');
    }

    /** A second upload adds to the first; it does not replace it. */
    public function test_a_later_upload_adds_to_the_existing_attachments(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);
        $as = $this->actingAs($tenant['employee'], 'sanctum');

        $as->postJson("/api/vouchers/{$voucher->id}/attachments", [
            'files' => [UploadedFile::fake()->create('invoice.pdf', 10, 'application/pdf')],
        ])->assertCreated();

        $as->postJson("/api/vouchers/{$voucher->id}/attachments", [
            'files' => [UploadedFile::fake()->image('receipt.jpg'), UploadedFile::fake()->image('scan.png')],
        ])->assertCreated();

        $this->assertSame(3, VoucherAttachment::withoutGlobalScopes()->where('voucher_id', $voucher->id)->count());
    }

    /** Someone in the same company who is not the author cannot add to a draft. */
    public function test_a_colleague_cannot_attach_to_someone_elses_draft(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        foreach (['hod', 'ceo', 'cashier'] as $role) {
            $status = $this->actingAs($tenant[$role], 'sanctum')
                ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                    'files' => [UploadedFile::fake()->create('invoice.pdf', 10, 'application/pdf')],
                ])->status();

            $this->assertContains($status, [403, 404], "{$role} was allowed to attach to the employee's draft");
        }

        $this->assertSame(0, VoucherAttachment::withoutGlobalScopes()->count());
    }

    /** Once submitted, the documents are what the approvers are deciding on. */
    public function test_a_submitted_voucher_refuses_new_attachments(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/submit")
            ->assertOk();

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->create('late-invoice.pdf', 10, 'application/pdf')],
            ])
            ->assertForbidden();

        $this->assertSame(0, VoucherAttachment::withoutGlobalScopes()->count());
    }

    /** image/* in a picker offers more than the server takes; the server still decides. */
    public function test_an_image_type_outside_the_allowed_list_is_refused(): void
    {
        $tenant = $this->makeTenant('Acme Trading');
        $voucher = $this->makeVoucher($tenant);

        $this->actingAs($tenant['employee'], 'sanctum')
            ->postJson("/api/vouchers/{$voucher->id}/attachments", [
                'files' => [UploadedFile::fake()->image('animation.gif')],
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('files.0');

        $this->assertSame(0, VoucherAttachment::withoutGlobalScopes()->count());
    }
}
