<?php

namespace App\Http\Controllers\Api\Erp\Fleet;

use App\Http\Controllers\Controller;
use App\Models\Erp\Fleet\FleetDowntime;
use App\Models\Erp\Fleet\FleetFuelIssue;
use App\Models\Erp\Fleet\FleetTrip;
use App\Models\Erp\Fleet\FleetVehicle;
use App\Services\AuditLogger;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/** The vehicle register: owned and hired vehicles, their papers and fixed costs. */
class VehicleController extends Controller
{
    public function __construct(private readonly TenantContext $tenant, private readonly AuditLogger $audit) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(FleetVehicle::query()
            ->with(['supplier:id,name', 'driver.user:id,name'])
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('ownership'), fn ($q, $v) => $q->where('ownership', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('registration_number', 'like', "%{$v}%")
                ->orWhere('make', 'like', "%{$v}%")->orWhere('model', 'like', "%{$v}%")))
            ->orderBy('registration_number')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(FleetVehicle $vehicle): JsonResponse
    {
        $vehicle->load(['supplier:id,name', 'driver.user:id,name', 'schedules', 'tyres' => fn ($q) => $q->latest('fitted_date'),
            'downtimes' => fn ($q) => $q->latest('started_at')->limit(20),
            'services' => fn ($q) => $q->with('supplier:id,name')->latest('service_date')->limit(30)]);

        $odometer = (float) $vehicle->odometer;
        $vehicle->schedules->each(fn ($s) => $s->setAttribute('state', $s->dueState($odometer)));

        return response()->json(['data' => [
            ...$vehicle->toArray(),
            'monthly_fixed_cost' => $vehicle->monthlyFixedCost(),
            'trips' => FleetTrip::query()->with(['driver.user:id,name', 'customer:id,name'])->where('vehicle_id', $vehicle->id)
                ->latest('planned_start')->limit(30)->get(),
            'fuel' => FleetFuelIssue::query()->with('trip:id,number')->where('vehicle_id', $vehicle->id)->latest('issue_date')->limit(30)->get(),
            'open_downtime' => FleetDowntime::query()->where('vehicle_id', $vehicle->id)->whereNull('ended_at')->first(),
        ]]);
    }

    public function store(Request $request): JsonResponse
    {
        $vehicle = FleetVehicle::create([...$this->rules($request), 'created_by' => $request->user()->id]);
        $this->audit->log('fleet.vehicle.created', "Registered vehicle {$vehicle->registration_number}", $vehicle);

        return response()->json(['data' => $vehicle], 201);
    }

    public function update(Request $request, FleetVehicle $vehicle): JsonResponse
    {
        $before = $vehicle->only(['registration_number', 'ownership', 'hire_rate', 'monthly_insurance', 'monthly_licence', 'monthly_depreciation']);
        $vehicle->update($this->rules($request, $vehicle));
        $this->audit->log('fleet.vehicle.updated', "Updated vehicle {$vehicle->registration_number}", $vehicle, $before,
            $vehicle->only(array_keys($before)));

        return response()->json(['data' => $vehicle]);
    }

    /** Takes a vehicle out of service or returns it, outside of trips and downtime. */
    public function status(Request $request, FleetVehicle $vehicle): JsonResponse
    {
        $status = $request->validate(['status' => ['required', Rule::in([FleetVehicle::STATUS_AVAILABLE, FleetVehicle::STATUS_OUT_OF_SERVICE])]])['status'];

        if ($vehicle->status === FleetVehicle::STATUS_ON_TRIP) {
            throw new RuntimeException("{$vehicle->registration_number} is on a trip. Complete the trip first.");
        }

        if (FleetDowntime::query()->where('vehicle_id', $vehicle->id)->whereNull('ended_at')->exists()) {
            throw new RuntimeException("{$vehicle->registration_number} has open downtime. End the downtime instead.");
        }

        $vehicle->update(['status' => $status]);
        $this->audit->log('fleet.vehicle.status', "{$vehicle->registration_number} set to ".str_replace('_', ' ', $status), $vehicle);

        return response()->json(['data' => $vehicle]);
    }

    /** @return array<string, mixed> */
    private function rules(Request $request, ?FleetVehicle $vehicle = null): array
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'registration_number' => ['required', 'string', 'max:30',
                Rule::unique('fleet_vehicles', 'registration_number')->where('company_id', $company)->ignore($vehicle?->id)],
            'make' => ['nullable', 'string', 'max:60'],
            'model' => ['nullable', 'string', 'max:60'],
            'type' => ['required', Rule::in(FleetVehicle::TYPES)],
            'year' => ['nullable', 'integer', 'between:1950,2100'],
            'capacity' => ['nullable', 'numeric', 'min:0'],
            'capacity_unit' => ['nullable', 'string', 'max:20'],
            'ownership' => ['required', Rule::in([FleetVehicle::OWNED, FleetVehicle::HIRED])],
            'supplier_id' => ['nullable', 'required_if:ownership,hired', 'integer', Rule::exists('suppliers', 'id')->where('company_id', $company)],
            'hire_rate_basis' => ['nullable', 'required_if:ownership,hired', Rule::in(FleetVehicle::HIRE_BASES)],
            'hire_rate' => ['nullable', 'required_if:ownership,hired', 'numeric', 'min:0'],
            'hire_includes_fuel' => ['boolean'],
            'odometer' => ['nullable', 'numeric', 'min:0'],
            'insurance_policy_number' => ['nullable', 'string', 'max:60'],
            'insurer' => ['nullable', 'string', 'max:120'],
            'insurance_expiry' => ['nullable', 'date'],
            'road_licence_number' => ['nullable', 'string', 'max:60'],
            'road_licence_expiry' => ['nullable', 'date'],
            'monthly_insurance' => ['nullable', 'numeric', 'min:0'],
            'monthly_licence' => ['nullable', 'numeric', 'min:0'],
            'monthly_depreciation' => ['nullable', 'numeric', 'min:0'],
            'monthly_other_fixed' => ['nullable', 'numeric', 'min:0'],
            'allocation_basis' => ['nullable', Rule::in(['days', 'km'])],
            'expected_monthly_km' => ['nullable', 'required_if:allocation_basis,km', 'numeric', 'min:1'],
            'notes' => ['nullable', 'string', 'max:1000'],
            'is_active' => ['boolean'],
        ]);

        $hired = $data['ownership'] === FleetVehicle::HIRED;

        if ($vehicle && $vehicle->ownership !== $data['ownership'] && $vehicle->trips()->exists()) {
            throw new RuntimeException("{$vehicle->registration_number} already has trips; its ownership cannot change.");
        }

        if ($vehicle && $vehicle->odometer !== null && isset($data['odometer']) && (float) $data['odometer'] < (float) $vehicle->odometer) {
            throw new RuntimeException('An odometer never goes backwards. Record a correction with a note instead.');
        }

        return [
            ...$data,
            'supplier_id' => $hired ? $data['supplier_id'] : null,
            'hire_rate_basis' => $hired ? $data['hire_rate_basis'] : null,
            'hire_rate' => $hired ? $data['hire_rate'] : null,
            'hire_includes_fuel' => $hired && ($data['hire_includes_fuel'] ?? false),
            'odometer' => $data['odometer'] ?? ($vehicle?->odometer ?? 0),
            'capacity_unit' => $data['capacity_unit'] ?? 'tonnes',
            'allocation_basis' => $data['allocation_basis'] ?? 'days',
            // A hired vehicle's fixed costs are its owner's, already inside the hire rate.
            'monthly_insurance' => $hired ? 0 : ($data['monthly_insurance'] ?? 0),
            'monthly_licence' => $hired ? 0 : ($data['monthly_licence'] ?? 0),
            'monthly_depreciation' => $hired ? 0 : ($data['monthly_depreciation'] ?? 0),
            'monthly_other_fixed' => $hired ? 0 : ($data['monthly_other_fixed'] ?? 0),
        ];
    }
}
