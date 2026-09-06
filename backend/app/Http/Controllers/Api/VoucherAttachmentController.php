<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\AttachmentResource;
use App\Models\Voucher;
use App\Models\VoucherAttachment;
use App\Services\AuditLogger;
use App\Services\UsageLimits;
use App\Services\VoucherVisibility;
use App\Services\WorkflowEngine;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

class VoucherAttachmentController extends Controller
{
    public function __construct(
        private readonly VoucherVisibility $visibility,
        private readonly WorkflowEngine $engine,
        private readonly UsageLimits $limits,
        private readonly AuditLogger $audit,
    ) {}

    public function store(Request $request, Voucher $voucher)
    {
        $this->authorizeVoucher($request, $voucher);

        abort_unless(
            $this->engine->availableActions($request->user(), $voucher)['edit'],
            403,
            'Attachments can only be added while the voucher is editable.',
        );

        $maxKb = (int) config('vouchflow.max_upload_mb', 10) * 1024;

        $request->validate([
            'files' => ['required', 'array', 'max:10'],
            'files.*' => ['required', 'file', "max:{$maxKb}", 'mimetypes:'.implode(',', config('vouchflow.allowed_upload_mimes'))],
        ], [
            'files.*.mimetypes' => 'Attachments must be a PDF or an image.',
            'files.*.max' => "Each attachment must be under {$maxKb} KB.",
        ]);

        $created = [];

        foreach ($request->file('files') as $file) {
            $this->limits->assertUploadSize($file->getSize());

            $path = $file->store("companies/{$voucher->company_id}/vouchers/{$voucher->id}", 'local');

            $created[] = VoucherAttachment::create([
                'voucher_id' => $voucher->id,
                'company_id' => $voucher->company_id,
                'uploaded_by' => $request->user()->id,
                'original_name' => $file->getClientOriginalName(),
                'path' => $path,
                'disk' => 'local',
                'mime_type' => $file->getClientMimeType(),
                'size_bytes' => $file->getSize(),
            ]);
        }

        $this->audit->log('voucher.attachment_added', count($created).' attachment(s) added to '.$voucher->number, $voucher);

        return AttachmentResource::collection(collect($created))->response()->setStatusCode(201);
    }

    /** Streams the file. Tenant scope on the model makes cross-company reads impossible. */
    public function show(Request $request, Voucher $voucher, VoucherAttachment $attachment)
    {
        $this->authorizeVoucher($request, $voucher);

        abort_unless($attachment->voucher_id === $voucher->id, 404);

        $disk = Storage::disk($attachment->disk ?: 'local');

        abort_unless($disk->exists($attachment->path), 404, 'That file is no longer stored.');

        return $disk->response($attachment->path, $attachment->original_name, [
            'Content-Type' => $attachment->mime_type ?: 'application/octet-stream',
        ]);
    }

    public function destroy(Request $request, Voucher $voucher, VoucherAttachment $attachment)
    {
        $this->authorizeVoucher($request, $voucher);

        abort_unless($attachment->voucher_id === $voucher->id, 404);
        abort_unless(
            $this->engine->availableActions($request->user(), $voucher)['edit'],
            403,
            'Attachments can only be removed while the voucher is editable.',
        );

        Storage::disk($attachment->disk ?: 'local')->delete($attachment->path);
        $attachment->delete();

        $this->audit->log('voucher.attachment_removed', "Removed {$attachment->original_name} from {$voucher->number}", $voucher);

        return response()->json(['message' => 'Attachment removed.']);
    }

    private function authorizeVoucher(Request $request, Voucher $voucher): void
    {
        $visible = $this->visibility
            ->apply(Voucher::query()->whereKey($voucher->id), $request->user())
            ->exists();

        if (! $visible) {
            throw new AccessDeniedHttpException('This voucher belongs to another part of the business.');
        }
    }
}
