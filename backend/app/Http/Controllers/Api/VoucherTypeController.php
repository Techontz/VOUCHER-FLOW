<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\VoucherTypeResource;
use App\Models\VoucherType;
use App\Services\AuditLogger;
use App\Support\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class VoucherTypeController extends Controller
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly TenantContext $tenant,
    ) {}

    public function index(Request $request)
    {
        return VoucherTypeResource::collection(
            VoucherType::withCount('vouchers')
                ->when(! $request->boolean('include_inactive'), fn ($q) => $q->where('is_active', true))
                ->orderBy('sort_order')->orderBy('name')
                ->get()
        );
    }

    public function store(Request $request)
    {
        $this->authorizeAdmin($request);

        $type = VoucherType::create($this->rules($request) + [
            'current_year' => (int) now()->format('Y'),
        ]);

        $this->audit->log('voucher_type.created', "Created voucher type {$type->name}", $type);

        return (new VoucherTypeResource($type))->response()->setStatusCode(201);
    }

    public function update(Request $request, VoucherType $voucherType)
    {
        $this->authorizeAdmin($request);

        $before = $voucherType->only(['name', 'prefix', 'next_number']);
        $voucherType->update($this->rules($request, $voucherType->id));

        $this->audit->log(
            'voucher_type.updated',
            "Updated voucher type {$voucherType->name}",
            $voucherType,
            $before,
            $voucherType->only(['name', 'prefix', 'next_number']),
        );

        return new VoucherTypeResource($voucherType->fresh());
    }

    public function destroy(Request $request, VoucherType $voucherType)
    {
        $this->authorizeAdmin($request);

        abort_if(
            $voucherType->vouchers()->exists(),
            422,
            'Vouchers of this type exist. Deactivate the type instead of deleting it.',
        );

        $name = $voucherType->name;
        $voucherType->delete();

        $this->audit->log('voucher_type.deleted', "Deleted voucher type {$name}", $voucherType);

        return response()->json(['message' => "Voucher type {$name} deleted."]);
    }

    private function rules(Request $request, ?int $ignoreId = null): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'name_sw' => ['nullable', 'string', 'max:120'],
            'code' => [
                'required', 'string', 'max:20',
                Rule::unique('voucher_types')->where('company_id', $this->tenant->id())->ignore($ignoreId),
            ],
            'prefix' => ['required', 'string', 'max:10'],
            'number_format' => ['nullable', 'string', 'max:60'],
            'seq_padding' => ['nullable', 'integer', 'min:1', 'max:10'],
            'next_number' => ['nullable', 'integer', 'min:1'],
            'reset_yearly' => ['nullable', 'boolean'],
            'is_active' => ['nullable', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
        ]);
    }

    private function authorizeAdmin(Request $request): void
    {
        abort_unless($request->user()->isAdmin(), 403, 'Only an administrator may change voucher types.');
    }
}
