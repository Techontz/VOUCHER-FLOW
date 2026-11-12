<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\AuditLog;
use App\Models\Erp\Documents\Document;
use App\Models\Erp\Documents\DocumentAccessLog;
use App\Models\Erp\Documents\DocumentVersion;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;
use Tests\TestSupport;

/**
 * Document management: files on the private disk, opened only through the
 * authorised download, only by those a folder and document are shared with;
 * versions kept; retention honoured; another company's documents invisible.
 * Acceptance criterion 13 for documents lives here.
 */
class ErpDocumentsTest extends TestCase
{
    use RefreshDatabase, TestSupport;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('local');
    }

    /** @return array<string, mixed> */
    private function dms(string $name = 'Maji Bora'): array
    {
        $erp = $this->setUpErp($this->makeTenant($name));
        $company = $erp['company'];
        $company->forceFill(['modules' => array_values(array_unique([...($company->modules ?? []), 'crm', 'documents']))])->save();

        $hr = User::create([
            'company_id' => $company->id, 'name' => "HR {$company->slug}", 'email' => "hr@{$company->slug}.test",
            'password' => 'Password123!', 'role' => User::ROLE_HR_MANAGER, 'status' => 'active',
        ]);

        return [...$erp, 'company' => $company->fresh(), 'hr' => $hr];
    }

    private function pdf(string $name = 'certificate.pdf', int $kb = 12): UploadedFile
    {
        return UploadedFile::fake()->createWithContent($name, "%PDF-1.4\n".str_repeat('x', $kb * 1024)."\n%%EOF");
    }

    private function folder(User $as, array $data): int
    {
        return $this->actingAs($as, 'sanctum')->postJson('/api/erp/files/folders', $data)->assertCreated()->json('data.id');
    }

    private function upload(User $as, array $data = [], ?UploadedFile $file = null): int
    {
        return $this->actingAs($as, 'sanctum')
            ->post('/api/erp/files/documents', ['file' => $file ?? $this->pdf(), ...$data], ['Accept' => 'application/json'])
            ->assertCreated()->json('data.id');
    }

    public function test_people_cannot_see_documents_outside_their_access(): void
    {
        $dms = $this->dms();
        $hrFolder = $this->folder($dms['admin'], ['name' => 'HR policies', 'access_scope' => 'roles', 'access_roles' => ['hr_manager']]);
        $inside = $this->folder($dms['admin'], ['name' => 'Payroll', 'parent_id' => $hrFolder]);
        $public = $this->folder($dms['admin'], ['name' => 'Company']);

        $payroll = $this->upload($dms['admin'], ['title' => 'Salary scale', 'folder_id' => $inside]);
        $handbook = $this->upload($dms['admin'], ['title' => 'Staff handbook', 'folder_id' => $public]);
        $private = $this->upload($dms['admin'], ['title' => 'Board minutes', 'folder_id' => $public, 'access_scope' => 'users', 'access_users' => [$dms['ceo']->id]]);

        // An employee sees the company folder and the handbook, nothing else.
        $this->actingAs($dms['employee'], 'sanctum');
        $this->getJson('/api/erp/files/browse')->assertOk()->assertJsonCount(1, 'folders')->assertJsonPath('folders.0.name', 'Company');
        $this->getJson("/api/erp/files/browse?folder_id={$public}")->assertOk()->assertJsonCount(1, 'documents.data');
        $this->getJson("/api/erp/files/browse?folder_id={$inside}")->assertNotFound();
        $this->getJson("/api/erp/files/documents/{$payroll}")->assertNotFound();
        $this->get("/api/erp/files/documents/{$payroll}/download")->assertNotFound();
        $this->get("/api/erp/files/documents/{$private}/download")->assertNotFound();
        $this->getJson("/api/erp/files/documents/{$handbook}")->assertOk();
        $this->getJson('/api/erp/files/documents')->assertOk()->assertJsonCount(1, 'data');
        $this->getJson('/api/erp/files/documents?q=Salary')->assertJsonCount(0, 'data');

        // The HR manager passes the HR folder and the sub-folder under it.
        $this->actingAs($dms['hr'], 'sanctum')->get("/api/erp/files/documents/{$payroll}/download")->assertOk();
        $this->getJson('/api/erp/files/documents')->assertJsonCount(2, 'data');

        // The named CEO opens the minutes; nobody else below a manager does.
        $this->actingAs($dms['ceo'], 'sanctum')->getJson("/api/erp/files/documents/{$private}")->assertOk();
        $this->actingAs($dms['hr'], 'sanctum')->getJson("/api/erp/files/documents/{$private}")->assertNotFound();

        // Uploading needs the permission, and into a folder the uploader can open.
        $this->actingAs($dms['employee'], 'sanctum')
            ->post('/api/erp/files/documents', ['file' => $this->pdf()], ['Accept' => 'application/json'])->assertForbidden();
        $this->actingAs($dms['accountant'], 'sanctum')
            ->post('/api/erp/files/documents', ['file' => $this->pdf(), 'folder_id' => $hrFolder], ['Accept' => 'application/json'])->assertNotFound();

        // Folders are shaped by managers only.
        $this->actingAs($dms['hr'], 'sanctum')->postJson('/api/erp/files/folders', ['name' => 'Mine'])->assertForbidden();
    }

    public function test_files_are_private_and_only_leave_through_the_authorised_download(): void
    {
        $dms = $this->dms();
        $id = $this->upload($dms['admin'], ['title' => 'TBS certificate']);
        $version = DocumentVersion::acrossTenants()->where('document_id', $id)->firstOrFail();

        // Stored on the private disk, never under the public one, and the path is never sent.
        Storage::disk('local')->assertExists($version->path);
        $this->assertStringStartsWith("companies/{$dms['company']->id}/documents/{$id}/", $version->path);
        $shown = $this->getJson("/api/erp/files/documents/{$id}")->assertOk()->json('data');
        $this->assertStringNotContainsString($version->path, json_encode($shown));

        // No token, no file.
        $this->app['auth']->forgetGuards();
        $this->getJson("/api/erp/files/documents/{$id}/download")->assertUnauthorized();

        // The download streams the bytes and records who took them.
        $response = $this->actingAs($dms['employee'], 'sanctum')->get("/api/erp/files/documents/{$id}/download")->assertOk();
        $this->assertStringStartsWith('%PDF', $response->streamedContent());
        $this->assertSame(1, DocumentAccessLog::acrossTenants()->where('document_id', $id)->where('action', 'download')->where('user_id', $dms['employee']->id)->count());

        // The access trail is a manager's view.
        $this->actingAs($dms['admin'], 'sanctum')->getJson("/api/erp/files/documents/{$id}")
            ->assertJsonPath('data.access_log.0.action', 'view');
    }

    public function test_uploads_are_checked_for_type_and_size(): void
    {
        $dms = $this->dms();
        $this->actingAs($dms['admin'], 'sanctum');

        $this->post('/api/erp/files/documents', ['file' => UploadedFile::fake()->createWithContent('run.php', '<?php echo 1;')], ['Accept' => 'application/json'])
            ->assertStatus(422)->assertJsonValidationErrors('file');
        $this->post('/api/erp/files/documents', ['file' => UploadedFile::fake()->create('huge.pdf', 21 * 1024, 'application/pdf')], ['Accept' => 'application/json'])
            ->assertStatus(422)->assertJsonValidationErrors('file');
        $this->post('/api/erp/files/documents', ['file' => UploadedFile::fake()->createWithContent('stock.csv', "sku,qty\nWTR-500,10\n")], ['Accept' => 'application/json'])
            ->assertCreated();
    }

    public function test_new_versions_keep_the_history(): void
    {
        $dms = $this->dms();
        $id = $this->upload($dms['admin'], ['title' => 'Supply contract'], UploadedFile::fake()->createWithContent('contract-v1.pdf', "%PDF-1.4\nfirst\n%%EOF"));

        $this->post("/api/erp/files/documents/{$id}/versions", [
            'file' => UploadedFile::fake()->createWithContent('contract-v2.pdf', "%PDF-1.4\nsecond\n%%EOF"), 'note' => 'Signed copy',
        ], ['Accept' => 'application/json'])->assertCreated()->assertJsonPath('data.version', 2);

        $this->getJson("/api/erp/files/documents/{$id}")->assertOk()
            ->assertJsonPath('data.current_version', 2)
            ->assertJsonCount(2, 'data.versions')
            ->assertJsonPath('data.versions.0.original_name', 'contract-v2.pdf')
            ->assertJsonPath('data.versions.1.original_name', 'contract-v1.pdf');

        $this->assertStringContainsString('second', $this->get("/api/erp/files/documents/{$id}/download")->streamedContent());
        $this->assertStringContainsString('first', $this->get("/api/erp/files/documents/{$id}/download?version=1")->streamedContent());

        // Someone else who can see it but did not upload it cannot replace it.
        $this->actingAs($dms['accountant'], 'sanctum')
            ->post("/api/erp/files/documents/{$id}/versions", ['file' => $this->pdf()], ['Accept' => 'application/json'])->assertStatus(422);
        $this->assertSame(2, DocumentVersion::acrossTenants()->where('document_id', $id)->count());
    }

    public function test_retention_blocks_early_deletion_and_a_manager_restores(): void
    {
        $dms = $this->dms();
        $contracts = $this->folder($dms['admin'], ['name' => 'Contracts', 'retention_years' => 7]);
        $kept = $this->upload($dms['admin'], ['title' => 'Lease', 'folder_id' => $contracts]);
        $loose = $this->upload($dms['admin'], ['title' => 'Old flyer']);

        $this->getJson("/api/erp/files/documents/{$kept}")->assertJsonPath('data.retained', true)
            ->assertJsonPath('data.retain_until', today()->addYears(7)->toDateString().'T00:00:00.000000Z');

        $this->deleteJson("/api/erp/files/documents/{$kept}")->assertStatus(422);
        $this->postJson("/api/erp/files/documents/{$kept}/retention", ['retention_years' => 1])->assertStatus(422);
        $this->assertNotSoftDeleted('dms_documents', ['id' => $kept]);

        // Only documents.delete may delete; the HR manager may not.
        $this->actingAs($dms['hr'], 'sanctum')->deleteJson("/api/erp/files/documents/{$loose}")->assertForbidden();

        $this->actingAs($dms['admin'], 'sanctum')->deleteJson("/api/erp/files/documents/{$loose}")->assertOk();
        $this->assertSoftDeleted('dms_documents', ['id' => $loose]);
        $this->getJson("/api/erp/files/documents/{$loose}")->assertNotFound();
        $this->getJson('/api/erp/files/documents?deleted=1')->assertJsonCount(1, 'data');
        $this->actingAs($dms['ceo'], 'sanctum')->postJson("/api/erp/files/documents/{$loose}/restore")->assertOk();
        $this->assertNotSoftDeleted('dms_documents', ['id' => $loose]);
        $this->assertTrue(AuditLog::where('action', 'document.restored')->exists());
    }

    public function test_links_expiry_and_another_companys_documents(): void
    {
        $mine = $this->dms('Maji Bora');
        $theirs = $this->dms('Zamani Freight');

        $insurance = $this->upload($mine['admin'], [
            'title' => 'Vehicle insurance T 123 ABC', 'document_type' => 'insurance', 'expires_on' => today()->addDays(12)->toDateString(),
            'links' => [['type' => 'vehicle', 'id' => 7], ['type' => 'supplier', 'id' => $mine['supplier']->id]],
        ]);
        $this->upload($mine['admin'], ['title' => 'Far off', 'expires_on' => today()->addYear()->toDateString()]);

        $this->getJson('/api/erp/files/expiring?days=30')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.days_left', 12);
        $this->getJson('/api/erp/files/linked?type=vehicle&id=7')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $insurance);
        $this->getJson("/api/erp/files/linked?type=supplier&id={$mine['supplier']->id}")->assertJsonCount(1, 'data');

        // A record from another company cannot be linked.
        $this->postJson("/api/erp/files/documents/{$insurance}/links", ['type' => 'supplier', 'id' => $theirs['supplier']->id])->assertStatus(422);

        $theirDoc = $this->upload($theirs['admin'], ['title' => 'Their licence']);

        $this->actingAs($mine['admin'], 'sanctum');
        $this->getJson("/api/erp/files/documents/{$theirDoc}")->assertNotFound();
        $this->get("/api/erp/files/documents/{$theirDoc}/download")->assertNotFound();
        $this->deleteJson("/api/erp/files/documents/{$theirDoc}")->assertNotFound();
        $this->getJson('/api/erp/files/documents')->assertJsonCount(2, 'data');
        $this->assertSame(1, app(TenantContext::class)->forCompany($theirs['company'], fn () => Document::count()));
    }

    public function test_owners_and_managers_are_alerted_at_each_expiry_milestone(): void
    {
        $dms = $this->dms();
        $id = $this->upload($dms['hr'], ['title' => 'Fire certificate', 'expires_on' => today()->addDays(7)->toDateString()]);
        $this->upload($dms['hr'], ['title' => 'Not yet', 'expires_on' => today()->addDays(9)->toDateString()]);

        $this->artisan('documents:expiry-alerts')->assertSuccessful();

        $alerts = AppNotification::where('type', 'document_expiring')->get();
        $this->assertEqualsCanonicalizing([$dms['hr']->id, $dms['admin']->id, $dms['ceo']->id], $alerts->pluck('user_id')->all());
        $this->assertSame("/erp/files/{$id}", $alerts->first()->action_url);
    }
}
