<?php

namespace App\Http\Controllers\Api\Erp\Fleet;

use App\Http\Controllers\Controller;
use App\Models\Erp\Fleet\FleetFuelStandard;
use App\Services\AuditLogger;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/** Fuel consumption standards per vehicle, per route, or per vehicle on a route. */
class FuelStandardController extends Controller
{
    public function __construct(private readonly TenantContext $tenant, private readonly AuditLogger $audit) {}

    public function index(): JsonResponse
    {
        return response()->json(['data' => FleetFuelStandard::query()->with('vehicle:id,registration_number')
            ->orderBy('vehicle_id')->orderBy('origin')->get()]);
    }

    public function store(Request $request): JsonResponse
    {
        $standard = FleetFuelStandard::create($this->rules($request));
        $this->audit->log('fleet.standard.created', 'Added a fuel standard', $standard);

        return response()->json(['data' => $standard->load('vehicle:id,registration_number')], 201);
    }

    public function update(Request $request, FleetFuelStandard $standard): JsonResponse
    {
        $standard->update($this->rules($request));
        $this->audit->log('fleet.standard.updated', 'Changed a fuel standard', $standard);

        return response()->json(['data' => $standard->load('vehicle:id,registration_number')]);
    }

    public function destroy(FleetFuelStandard $standard): JsonResponse
    {
        // Trips keep the litres they were judged against, so removing a standard rewrites nothing.
        $standard->delete();
        $this->audit->log('fleet.standard.deleted', 'Removed a fuel standard', $standard);

        return response()->json(['message' => 'Fuel standard removed.']);
    }

    /** @return array<string, mixed> */
    private function rules(Request $request): array
    {
        $data = $request->validate([
            'vehicle_id' => ['nullable', 'integer', Rule::exists('fleet_vehicles', 'id')->where('company_id', $this->tenant->id())],
            'origin' => ['nullable', 'required_with:destination', 'string', 'max:80'],
            'destination' => ['nullable', 'required_with:origin', 'string', 'max:80'],
            'basis' => ['required', Rule::in([FleetFuelStandard::PER_100KM, FleetFuelStandard::PER_TRIP])],
            'litres' => ['required', 'numeric', 'gt:0'],
            'tolerance_percent' => ['nullable', 'numeric', 'between:0,100'],
            'notes' => ['nullable', 'string', 'max:255'],
            'is_active' => ['boolean'],
        ]);

        if (empty($data['vehicle_id']) && empty($data['origin'])) {
            throw new RuntimeException('A standard is for a vehicle, a route, or a vehicle on a route.');
        }

        if ($data['basis'] === FleetFuelStandard::PER_TRIP && empty($data['origin'])) {
            throw new RuntimeException('Litres per trip only make sense for a route.');
        }

        return [...$data, 'tolerance_percent' => $data['tolerance_percent'] ?? 10];
    }
}
