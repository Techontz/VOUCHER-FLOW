<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\AuditLogResource;
use App\Models\AuditLog;
use App\Support\TenantContext;
use Illuminate\Http\Request;

class AuditLogController extends Controller
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function index(Request $request)
    {
        $user = $request->user();

        abort_unless($user->isAdmin(), 403, 'Only an administrator may read the audit log.');

        $logs = AuditLog::query()
            ->with('company')
            // A company admin is pinned to their own tenant; only the platform
            // super admin may read across companies.
            ->when(! $user->isSuperAdmin(), fn ($q) => $q->where('company_id', $this->tenant->id()))
            ->when($user->isSuperAdmin() && $request->query('company_id'), fn ($q, $v) => $q->where('company_id', $v))
            ->when($request->query('action'), fn ($q, $v) => $q->where('action', 'like', $v.'%'))
            ->when($request->query('actor_id'), fn ($q, $v) => $q->where('actor_id', $v))
            ->when($request->query('entity_type'), fn ($q, $v) => $q->where('entity_type', $v))
            ->when($request->query('from'), fn ($q, $v) => $q->whereDate('created_at', '>=', $v))
            ->when($request->query('to'), fn ($q, $v) => $q->whereDate('created_at', '<=', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w
                ->where('description', 'like', "%{$v}%")
                ->orWhere('actor_name', 'like', "%{$v}%")))
            ->latest('id')
            ->paginate((int) $request->query('per_page', 30))
            ->withQueryString();

        return AuditLogResource::collection($logs);
    }

    /** The distinct actions recorded, for the filter dropdown. */
    public function actions(Request $request)
    {
        abort_unless($request->user()->isAdmin(), 403);

        $actions = AuditLog::query()
            ->when(! $request->user()->isSuperAdmin(), fn ($q) => $q->where('company_id', $this->tenant->id()))
            ->distinct()
            ->orderBy('action')
            ->pluck('action');

        return response()->json(['data' => $actions]);
    }
}
