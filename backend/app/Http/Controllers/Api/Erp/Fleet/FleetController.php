<?php

namespace App\Http\Controllers\Api\Erp\Fleet;

use App\Http\Controllers\Controller;
use App\Models\Erp\Account;
use App\Models\Erp\Customer;
use App\Models\Erp\Fleet\FleetDriver;
use App\Models\Erp\Fleet\FleetVehicle;
use App\Models\Erp\Supplier;
use App\Services\Erp\Fleet\FleetReports;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** The fleet overview, the pick-lists the fleet forms need, and the profitability report. */
class FleetController extends Controller
{
    public function __construct(private readonly FleetReports $reports, private readonly TenantContext $tenant) {}

    public function overview(): JsonResponse
    {
        return response()->json(['data' => $this->reports->overview()]);
    }

    /**
     * Everything a fleet form chooses from. Served here, under the fleet
     * permissions, so a dispatcher can pick a customer without holding the
     * sales module's customer permissions.
     */
    public function lookups(): JsonResponse
    {
        return response()->json(['data' => [
            'vehicles' => FleetVehicle::query()->where('is_active', true)->orderBy('registration_number')
                ->get(['id', 'registration_number', 'make', 'model', 'ownership', 'status', 'odometer', 'hire_includes_fuel', 'hire_rate_basis', 'hire_rate', 'supplier_id']),
            'drivers' => FleetDriver::query()->with('user:id,name')->where('is_active', true)->get(['id', 'user_id', 'vehicle_id', 'daily_allowance', 'licence_expiry'])
                ->map(fn ($d) => ['id' => $d->id, 'name' => $d->user?->name, 'vehicle_id' => $d->vehicle_id, 'daily_allowance' => $d->daily_allowance, 'licence_expiry' => $d->licence_expiry?->toDateString()])
                ->sortBy('name')->values(),
            'customers' => Customer::query()->where('is_active', true)->orderBy('name')->get(['id', 'code', 'name']),
            ...$this->paymentLookups(),
        ]]);
    }

    /** What a driver needs to record fuel and expenses on their own trips. */
    public function myLookups(): JsonResponse
    {
        return response()->json(['data' => $this->paymentLookups()]);
    }

    public function profitability(Request $request): JsonResponse
    {
        $data = $request->validate([
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date', 'after_or_equal:from'],
            'vehicle_id' => ['nullable', 'integer', Rule::exists('fleet_vehicles', 'id')->where('company_id', $this->tenant->id())],
        ]);

        return response()->json(['data' => $this->reports->profitability($data['from'] ?? null, $data['to'] ?? null, isset($data['vehicle_id']) ? (int) $data['vehicle_id'] : null)]);
    }

    /** @return array<string, mixed> */
    private function paymentLookups(): array
    {
        return [
            'suppliers' => Supplier::query()->where('is_active', true)->orderBy('name')->get(['id', 'code', 'name', 'category']),
            'accounts' => Account::query()->where('type', 'asset')->where('is_active', true)
                ->whereBetween('code', ['1100', '1299'])->orderBy('code')->get(['id', 'code', 'name']),
        ];
    }
}
