<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\CommentResource;
use App\Models\Voucher;
use App\Models\VoucherComment;
use App\Services\Notifier;
use App\Services\VoucherVisibility;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

class VoucherCommentController extends Controller
{
    public function __construct(
        private readonly VoucherVisibility $visibility,
        private readonly Notifier $notifier,
    ) {}

    public function store(Request $request, Voucher $voucher)
    {
        if (Gate::forUser($request->user())->denies('view', $voucher)) {
            throw new AccessDeniedHttpException('This voucher belongs to another part of the business.');
        }

        $data = $request->validate(['body' => ['required', 'string', 'max:2000']]);

        $comment = VoucherComment::create([
            'voucher_id' => $voucher->id,
            'company_id' => $voucher->company_id,
            'user_id' => $request->user()->id,
            'body' => $data['body'],
        ]);

        if ($voucher->requester_id !== $request->user()->id) {
            $this->notifier->toUser(
                $voucher->requester,
                'voucher.comment',
                "New comment on {$voucher->number}",
                "Maoni mapya kwenye {$voucher->number}",
                $request->user()->name.': '.$data['body'],
                $request->user()->name.': '.$data['body'],
                $voucher,
                'ph-chat-circle-text',
            );
        }

        return (new CommentResource($comment->load('user.department')))->response()->setStatusCode(201);
    }

    public function destroy(Request $request, Voucher $voucher, VoucherComment $comment)
    {
        abort_unless($comment->voucher_id === $voucher->id, 404);
        abort_unless(
            $comment->user_id === $request->user()->id || $request->user()->isAdmin(),
            403,
            'You can only remove your own comment.',
        );

        $comment->delete();

        return response()->json(['message' => 'Comment removed.']);
    }
}
