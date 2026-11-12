<?php

namespace App\Http\Controllers\Api\Erp\Fleet;

use App\Http\Controllers\Controller;
use App\Models\Erp\Fleet\FleetDriver;
use App\Models\Erp\Fleet\FleetTrip;
use App\Models\User;
use App\Services\AuditLogger;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/** Drivers: a user with the driver role, their licence and the vehicle they are assigned to. */
class DriverController extends Controller
{
    public function __construct(private readonly TenantContext $tenant, private readonly AuditLogger $audit) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json(FleetDriver::query()
            ->with(['user:id,name,email,phone', 'vehicle:id,registration_number'])
            ->withCount(['trips as open_trips_count' => fn ($q) => $q->whereIn('status', [FleetTrip::STATUS_PLANNED, FleetTrip::STATUS_DISPATCHED])])
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('licence_number', 'like', "%{$v}%")
                ->orWhereHas('user', fn ($u) => $u->where('name', 'like', "%{$v}%"))))
            ->orderByDesc('is_active')->orderBy('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function show(FleetDriver $driver): JsonResponse
    {
        return response()->json(['data' => [
            ...$driver->load(['user:id,name,email,phone', 'vehicle:id,registration_number'])->toArray(),
            'trips' => $driver->trips()->with(['vehicle:id,registration_number', 'customer:id,name'])->latest('planned_start')->limit(30)->get(),
        ]]);
    }

    /** People with the driver role who are not yet on the register. */
    public function candidates(): JsonResponse
    {
        $registered = FleetDriver::query()->pluck('user_id');

        return response()->json(['data' => User::query()->where('company_id', $this->tenant->id())
            ->where('role', User::ROLE_DRIVER)->whereNotIn('id', $registered)
            ->orderBy('name')->get(['id', 'name', 'email', 'phone'])]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->rules($request);
        $driver = FleetDriver::create($data);
        $this->audit->log('fleet.driver.created', "Registered driver {$driver->user?->name}", $driver);

        return response()->json(['data' => $driver->load('user:id,name', 'vehicle:id,registration_number')], 201);
    }

    public function update(Request $request, FleetDriver $driver): JsonResponse
    {
        $data = $this->rules($request, $driver);
        $driver->update($data);
        $this->audit->log('fleet.driver.updated', "Updated driver {$driver->user?->name}", $driver);

        return response()->json(['data' => $driver->load('user:id,name', 'vehicle:id,registration_number')]);
    }

    /** @return array<string, mixed> */
    private function rules(Request $request, ?FleetDriver $driver = null): array
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'user_id' => [$driver ? 'prohibited' : 'required', 'integer',
                Rule::exists('users', 'id')->where('company_id', $company),
                Rule::unique('fleet_drivers', 'user_id')->where('company_id', $company)],
            'licence_number' => ['required', 'string', 'max:40',
                Rule::unique('fleet_drivers', 'licence_number')->where('company_id', $company)->ignore($driver?->id)],
            'licence_class' => ['nullable', 'string', 'max:20'],
            'licence_expiry' => ['nullable', 'date'],
            'phone' => ['nullable', 'string', 'max:40'],
            'vehicle_id' => ['nullable', 'integer', Rule::exists('fleet_vehicles', 'id')->where('company_id', $company)],
            'daily_allowance' => ['nullable', 'numeric', 'min:0'],
            'is_active' => ['boolean'],
        ]);

        if (! $driver) {
            $user = User::query()->findOrFail($data['user_id']);
            if ($user->role !== User::ROLE_DRIVER) {
                throw new RuntimeException("{$user->name} does not have the driver role. Change their role under Employees first.");
            }
        }

        // One driver per vehicle: assigning here releases whoever held it.
        if (! empty($data['vehicle_id'])) {
            FleetDriver::query()->where('vehicle_id', $data['vehicle_id'])->when($driver, fn ($q) => $q->whereKeyNot($driver->id))
                ->update(['vehicle_id' => null]);
        }

        return [...$data, 'daily_allowance' => $data['daily_allowance'] ?? 0];
    }
}
