<?php

namespace App\Http\Controllers\Api\Erp\Fleet;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Erp\Fleet\FleetFuelIssue;
use App\Models\Erp\Fleet\FleetTrip;
use App\Models\Erp\Fleet\FleetTripExpense;
use App\Models\Erp\JournalEntry;
use App\Services\Erp\Fleet\FleetTrips;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Trips, their fuel and expenses.
 *
 * The same reads serve two audiences: people with fleet.view see every trip;
 * drivers (fleet.own) reach them through /fleet/my-trips and see only trips
 * they drive. Another driver's trip is a 404 to them, not a 403.
 */
class TripController extends Controller
{
    public function __construct(private readonly FleetTrips $trips, private readonly TenantContext $tenant) {}

    public function index(Request $request): JsonResponse
    {
        return response()->json($this->listing($request, FleetTrip::query()));
    }

    public function myIndex(Request $request): JsonResponse
    {
        return response()->json($this->listing($request, $this->own($request)));
    }

    public function show(FleetTrip $trip): JsonResponse
    {
        return response()->json(['data' => $this->detail($trip)]);
    }

    public function myShow(Request $request, int $trip): JsonResponse
    {
        // A driver sees the trip and its entries, not the ledger behind it.
        $detail = $this->detail($this->own($request)->findOrFail($trip));
        unset($detail['journals'], $detail['timeline'], $detail['allocations']);

        return response()->json(['data' => $detail]);
    }

    public function store(Request $request): JsonResponse
    {
        $trip = $this->trips->create($this->rules($request), $request->user());

        return response()->json(['data' => $this->detail($trip)], 201);
    }

    public function update(Request $request, FleetTrip $trip): JsonResponse
    {
        return response()->json(['data' => $this->detail($this->trips->update($trip, $this->rules($request), $request->user()))]);
    }

    public function dispatchTrip(Request $request, FleetTrip $trip): JsonResponse
    {
        $data = $request->validate([
            'odometer_out' => ['nullable', 'numeric', 'min:0'],
            'at' => ['nullable', 'date', 'before_or_equal:now'],
        ]);
        $trip = $this->trips->dispatch($trip, isset($data['odometer_out']) ? (float) $data['odometer_out'] : null, $data['at'] ?? null, $request->user());

        return response()->json(['message' => "{$trip->number} dispatched.", 'data' => $this->detail($trip)]);
    }

    public function complete(Request $request, FleetTrip $trip): JsonResponse
    {
        $data = $request->validate([
            'odometer_in' => ['nullable', 'numeric', 'min:0'],
            'at' => ['nullable', 'date', 'before_or_equal:now'],
        ]);
        $trip = $this->trips->complete($trip, isset($data['odometer_in']) ? (float) $data['odometer_in'] : null, $data['at'] ?? null, $request->user());

        return response()->json(['message' => "{$trip->number} completed.", 'data' => $this->detail($trip)]);
    }

    public function close(Request $request, FleetTrip $trip): JsonResponse
    {
        $note = $request->validate(['note' => ['nullable', 'string', 'max:255']])['note'] ?? null;
        $trip = $this->trips->close($trip, $note, $request->user());

        return response()->json(['message' => "{$trip->number} closed.", 'data' => $this->detail($trip)]);
    }

    public function cancel(Request $request, FleetTrip $trip): JsonResponse
    {
        $reason = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:255']])['reason'];
        $trip = $this->trips->cancel($trip, $reason, $request->user());

        return response()->json(['message' => "{$trip->number} cancelled.", 'data' => $this->detail($trip)]);
    }

    /* ------------------------------------------------------------ fuel and expenses */

    public function fuelLog(Request $request): JsonResponse
    {
        return response()->json(FleetFuelIssue::query()
            ->with(['trip:id,number,origin,destination,fuel_over_standard', 'vehicle:id,registration_number', 'recorder:id,name', 'supplier:id,name', 'account:id,code,name'])
            ->when($request->query('vehicle_id'), fn ($q, $v) => $q->where('vehicle_id', $v))
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('from'), fn ($q, $v) => $q->whereDate('issue_date', '>=', $v))
            ->when($request->query('to'), fn ($q, $v) => $q->whereDate('issue_date', '<=', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('station', 'like', "%{$v}%")
                ->orWhere('receipt_number', 'like', "%{$v}%")->orWhereHas('trip', fn ($t) => $t->where('number', 'like', "%{$v}%"))))
            ->latest('issue_date')->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    /** Entries waiting for someone with fleet.approve. */
    public function pending(): JsonResponse
    {
        $with = ['trip:id,number,origin,destination', 'recorder:id,name'];

        return response()->json(['data' => [
            'fuel' => FleetFuelIssue::query()->with([...$with, 'vehicle:id,registration_number'])->where('status', FleetFuelIssue::PENDING)->oldest()->get(),
            'expenses' => FleetTripExpense::query()->with($with)->where('status', FleetFuelIssue::PENDING)->oldest()->get(),
        ]]);
    }

    public function storeFuel(Request $request, FleetTrip $trip): JsonResponse
    {
        $issue = $this->trips->recordFuel($trip, $this->fuelRules($request), $request->user());

        return response()->json(['message' => $this->recordedMessage($issue->status), 'data' => $issue], 201);
    }

    public function myStoreFuel(Request $request, int $trip): JsonResponse
    {
        return $this->storeFuel($request, $this->own($request)->findOrFail($trip));
    }

    public function storeExpense(Request $request, FleetTrip $trip): JsonResponse
    {
        $expense = $this->trips->recordExpense($trip, $this->expenseRules($request), $request->user());

        return response()->json(['message' => $this->recordedMessage($expense->status), 'data' => $expense], 201);
    }

    public function myStoreExpense(Request $request, int $trip): JsonResponse
    {
        return $this->storeExpense($request, $this->own($request)->findOrFail($trip));
    }

    public function decideFuel(Request $request, FleetFuelIssue $fuel): JsonResponse
    {
        return $this->decide($request, $fuel);
    }

    public function decideExpense(Request $request, FleetTripExpense $expense): JsonResponse
    {
        return $this->decide($request, $expense);
    }

    private function decide(Request $request, FleetFuelIssue|FleetTripExpense $entry): JsonResponse
    {
        $data = $request->validate([
            'decision' => ['required', Rule::in(['approve', 'reject'])],
            'reason' => ['nullable', 'required_if:decision,reject', 'string', 'max:255'],
        ]);
        $entry = $this->trips->decide($entry, $data['decision'] === 'approve', $data['reason'] ?? null, $request->user());

        return response()->json(['message' => $data['decision'] === 'approve' ? 'Approved.' : 'Rejected.', 'data' => $entry]);
    }

    /* ------------------------------------------------------------ shapes */

    /** @return Builder<FleetTrip> */
    private function own(Request $request): Builder
    {
        return FleetTrip::query()->whereHas('driver', fn ($q) => $q->where('user_id', $request->user()->id));
    }

    private function listing(Request $request, Builder $query): mixed
    {
        return $query
            ->with(['vehicle:id,registration_number,ownership', 'driver.user:id,name', 'customer:id,name'])
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('cost_option'), fn ($q, $v) => $q->where('cost_option', $v))
            ->when($request->query('vehicle_id'), fn ($q, $v) => $q->where('vehicle_id', $v))
            ->when($request->query('driver_id'), fn ($q, $v) => $q->where('driver_id', $v))
            ->when($request->boolean('over_standard'), fn ($q) => $q->where('fuel_over_standard', true))
            ->when($request->query('from'), fn ($q, $v) => $q->whereDate('planned_start', '>=', $v))
            ->when($request->query('to'), fn ($q, $v) => $q->whereDate('planned_start', '<=', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")
                ->orWhere('origin', 'like', "%{$v}%")->orWhere('destination', 'like', "%{$v}%")
                ->orWhere('source_reference', 'like', "%{$v}%")->orWhere('cargo_description', 'like', "%{$v}%")))
            ->latest('planned_start')->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100));
    }

    /** @return array<string, mixed> */
    private function detail(FleetTrip $trip): array
    {
        $trip = $trip->fresh([
            'vehicle.supplier:id,name', 'driver.user:id,name,phone', 'customer:id,code,name',
            'fuelIssues' => fn ($q) => $q->with(['recorder:id,name', 'approver:id,name', 'supplier:id,name', 'account:id,code,name'])->orderBy('issue_date'),
            'expenses' => fn ($q) => $q->with(['recorder:id,name', 'approver:id,name', 'supplier:id,name', 'account:id,code,name'])->orderBy('expense_date'),
            'allocations', 'creator:id,name', 'closer:id,name', 'varianceApprover:id,name',
        ]);
        $standard = $trip->vehicle_id ? $this->trips->standardFor($trip) : null;

        return [
            ...$trip->toArray(),
            'costs' => $this->trips->costs($trip),
            'standard' => $standard?->only(['id', 'basis', 'litres', 'tolerance_percent', 'origin', 'destination', 'vehicle_id']),
            'journals' => JournalEntry::query()->with('lines.account:id,code,name')
                ->where('source_type', 'FleetTrip')->where('source_id', $trip->id)->orderBy('id')->get(),
            'timeline' => AuditLog::query()->where('company_id', $this->tenant->id())
                ->where('entity_type', 'FleetTrip')->where('entity_id', $trip->id)
                ->orderBy('id')->get(['id', 'action', 'description', 'actor_name', 'created_at']),
        ];
    }

    private function recordedMessage(string $status): string
    {
        return $status === FleetFuelIssue::APPROVED ? 'Recorded and approved.' : 'Recorded. It waits for approval.';
    }

    /** @return array<string, mixed> */
    private function rules(Request $request): array
    {
        $company = $this->tenant->id();

        return $request->validate([
            'cost_option' => ['required', Rule::in(FleetTrip::OPTIONS)],
            'vehicle_id' => ['nullable', 'integer', Rule::exists('fleet_vehicles', 'id')->where('company_id', $company)],
            'driver_id' => ['nullable', 'integer', Rule::exists('fleet_drivers', 'id')->where('company_id', $company)],
            'external_vehicle' => ['nullable', 'string', 'max:60'],
            'customer_id' => ['nullable', 'integer', Rule::exists('customers', 'id')->where('company_id', $company)->whereNull('deleted_at')],
            'origin' => ['required', 'string', 'max:80'],
            'destination' => ['required', 'string', 'max:80', 'different:origin'],
            'distance_km' => ['nullable', 'numeric', 'min:0', 'max:100000'],
            'planned_start' => ['required', 'date'],
            'planned_end' => ['nullable', 'date', 'after_or_equal:planned_start'],
            'source_type' => ['nullable', 'string', 'max:40', 'required_with:source_id'],
            'source_id' => ['nullable', 'integer', 'min:1'],
            'source_reference' => ['nullable', 'string', 'max:80'],
            'cargo_description' => ['nullable', 'string', 'max:500'],
            'transport_charge' => ['nullable', 'numeric', 'min:0'],
            'notes' => ['nullable', 'string', 'max:1000'],
        ]);
    }

    /** @return array<string, mixed> */
    private function fuelRules(Request $request): array
    {
        return $request->validate([
            'issue_date' => ['nullable', 'date', 'before_or_equal:today'],
            'litres' => ['required', 'numeric', 'gt:0', 'max:100000'],
            'price_per_litre' => ['required', 'numeric', 'gt:0'],
            'station' => ['nullable', 'string', 'max:120'],
            'receipt_number' => ['nullable', 'string', 'max:60'],
            'odometer' => ['nullable', 'numeric', 'min:0'],
            ...$this->paymentRules(),
        ]);
    }

    /** @return array<string, mixed> */
    private function expenseRules(Request $request): array
    {
        return $request->validate([
            'type' => ['required', Rule::in(FleetTripExpense::TYPES)],
            'description' => ['nullable', 'required_if:type,other', 'string', 'max:255'],
            'expense_date' => ['nullable', 'date', 'before_or_equal:today'],
            'quantity' => ['nullable', 'numeric', 'gt:0', 'max:1000'],
            'rate' => ['nullable', 'numeric', 'gt:0'],
            'receipt_number' => ['nullable', 'string', 'max:60'],
            ...$this->paymentRules(),
        ]);
    }

    /** @return array<string, mixed> */
    private function paymentRules(): array
    {
        $company = $this->tenant->id();

        return [
            'account_id' => ['nullable', 'integer', Rule::exists('accounts', 'id')->where('company_id', $company)],
            'supplier_id' => ['nullable', 'integer', Rule::exists('suppliers', 'id')->where('company_id', $company)],
        ];
    }
}
