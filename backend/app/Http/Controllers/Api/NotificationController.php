<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\NotificationResource;
use App\Models\AppNotification;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function index(Request $request)
    {
        $notifications = AppNotification::where('user_id', $request->user()->id)
            ->when($request->boolean('unread_only'), fn ($q) => $q->whereNull('read_at'))
            ->latest('id')
            ->paginate((int) $request->query('per_page', 30));

        return NotificationResource::collection($notifications)->additional([
            'meta' => [
                'unread_count' => AppNotification::where('user_id', $request->user()->id)->whereNull('read_at')->count(),
            ],
        ]);
    }

    public function unreadCount(Request $request)
    {
        return response()->json([
            'unread_count' => AppNotification::where('user_id', $request->user()->id)->whereNull('read_at')->count(),
        ]);
    }

    public function markRead(Request $request, AppNotification $notification)
    {
        abort_unless($notification->user_id === $request->user()->id, 404);

        $notification->forceFill(['read_at' => now()])->save();

        return new NotificationResource($notification);
    }

    public function markAllRead(Request $request)
    {
        $count = AppNotification::where('user_id', $request->user()->id)
            ->whereNull('read_at')
            ->update(['read_at' => now()]);

        return response()->json(['message' => "{$count} notifications marked as read.", 'count' => $count]);
    }

    public function destroy(Request $request, AppNotification $notification)
    {
        abort_unless($notification->user_id === $request->user()->id, 404);

        $notification->delete();

        return response()->json(['message' => 'Notification removed.']);
    }
}
