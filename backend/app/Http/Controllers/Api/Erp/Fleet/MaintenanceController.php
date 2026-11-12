<?php

namespace App\Http\Controllers\Api\Erp\Fleet;

use App\Http\Controllers\Controller;
use App\Models\Erp\Fleet\FleetDowntime;
use App\Models\Erp\Fleet\FleetMaintenanceSchedule;
use App\Models\Erp\Fleet\FleetServiceRecord;
use App\Models\Erp\Fleet\FleetTyre;
use App\Models\Erp\JournalEntry;
use App\Services\AuditLogger;
use App\Services\Erp\Fleet\FleetMaintenance;
use App\Services\Erp\Fleet\FleetReports;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/** Maintenance schedules, service records, tyres and downtime. */
class MaintenanceController extends Controller
{
    public function __construct(
        private readonly FleetMaintenance $maintenance,
        private readonly FleetReports $reports,
        private readonly TenantContext $tenant,
        private readonly AuditLogger $audit,
    ) {}

    /* ------------------------------------------------------------ schedules */

    public function schedules(Request $request): JsonResponse
    {
        $rows = FleetMaintenanceSchedule::query()->with('vehicle:id,registration_number,odometer')
            ->when($request->query('vehicle_id'), fn ($q, $v) => $q->where('vehicle_id', $v))
            ->orderBy('vehicle_id')->orderBy('title')->get()
            ->map(fn ($s) => [...$s->toArray(), 'state' => $s->dueState((float) $s->vehicle?->odometer)]);

        return response()->json(['data' => $rows, 'due' => $this->reports->maintenanceDue()]);
    }

    public function storeSchedule(Request $request): JsonResponse
    {
        $schedule = new FleetMaintenanceSchedule($this->scheduleRules($request));
        $schedule->recomputeNextDue();
        $schedule->save();
        $this->audit->log('fleet.schedule.created', "Scheduled {$schedule->title}", $schedule);

        return response()->json(['data' => $schedule], 201);
    }

    public function updateSchedule(Request $request, FleetMaintenanceSchedule $schedule): JsonResponse
    {
        $schedule->fill($this->scheduleRules($request));
        $schedule->recomputeNextDue();
        $schedule->save();
        $this->audit->log('fleet.schedule.updated', "Changed schedule {$schedule->title}", $schedule);

        return response()->json(['data' => $schedule]);
    }

    public function destroySchedule(FleetMaintenanceSchedule $schedule): JsonResponse
    {
        $schedule->delete();
        $this->audit->log('fleet.schedule.deleted', "Removed schedule {$schedule->title}", $schedule);

        return response()->json(['message' => 'Schedule removed.']);
    }

    /* ------------------------------------------------------------ service records */

    public function services(Request $request): JsonResponse
    {
        return response()->json(FleetServiceRecord::query()
            ->with(['vehicle:id,registration_number', 'supplier:id,name', 'schedule:id,title', 'creator:id,name'])
            ->when($request->query('vehicle_id'), fn ($q, $v) => $q->where('vehicle_id', $v))
            ->when($request->query('status'), fn ($q, $v) => $q->where('status', $v))
            ->when($request->query('q'), fn ($q, $v) => $q->where(fn ($w) => $w->where('number', 'like', "%{$v}%")
                ->orWhere('work_done', 'like', "%{$v}%")->orWhere('invoice_number', 'like', "%{$v}%")))
            ->latest('service_date')->latest('id')
            ->paginate(min((int) $request->query('per_page', 30), 100)));
    }

    public function showService(FleetServiceRecord $service): JsonResponse
    {
        return response()->json(['data' => [
            ...$service->load(['vehicle:id,registration_number,odometer', 'supplier:id,name', 'account:id,code,name', 'schedule', 'creator:id,name', 'poster:id,name'])->toArray(),
            'journals' => JournalEntry::query()->with('lines.account:id,code,name')
                ->where('source_type', 'FleetServiceRecord')->where('source_id', $service->id)->get(),
        ]]);
    }

    public function storeService(Request $request): JsonResponse
    {
        return response()->json(['data' => $this->maintenance->createService($this->serviceRules($request), $request->user())], 201);
    }

    public function updateService(Request $request, FleetServiceRecord $service): JsonResponse
    {
        return response()->json(['data' => $this->maintenance->updateService($service, $this->serviceRules($request), $request->user())]);
    }

    public function postService(Request $request, FleetServiceRecord $service): JsonResponse
    {
        $record = $this->maintenance->postService($service, $request->user());

        return response()->json(['message' => "{$record->number} posted.", 'data' => $record]);
    }

    public function cancelService(Request $request, FleetServiceRecord $service): JsonResponse
    {
        return response()->json(['message' => 'Draft cancelled.', 'data' => $this->maintenance->cancelService($service, $request->user())]);
    }

    /* ------------------------------------------------------------ tyres */

    public function tyres(Request $request): JsonResponse
    {
        return response()->json(['data' => FleetTyre::query()->with('vehicle:id,registration_number,odometer')
            ->when($request->query('vehicle_id'), fn ($q, $v) => $q->where('vehicle_id', $v))
            ->when($request->query('state') === 'fitted', fn ($q) => $q->whereNull('removed_date'))
            ->when($request->query('state') === 'removed', fn ($q) => $q->whereNotNull('removed_date'))
            ->orderByRaw('removed_date is not null')->orderBy('vehicle_id')->orderBy('position')
            ->limit(500)->get()]);
    }

    public function storeTyre(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'vehicle_id' => ['required', 'integer', Rule::exists('fleet_vehicles', 'id')->where('company_id', $company)],
            'position' => ['required', 'string', 'max:30'],
            'serial_number' => ['required', 'string', 'max:60'],
            'brand' => ['nullable', 'string', 'max:60'],
            'size' => ['nullable', 'string', 'max:30'],
            'cost' => ['nullable', 'numeric', 'min:0'],
            'fitted_date' => ['nullable', 'date', 'before_or_equal:today'],
            'fitted_odometer' => ['nullable', 'numeric', 'min:0'],
        ]);

        if (FleetTyre::query()->where('serial_number', $data['serial_number'])->whereNotNull('removed_date')->exists()) {
            throw new RuntimeException("Tyre {$data['serial_number']} was fitted before and removed; a removed tyre keeps its history, so record a refit under a new serial.");
        }

        return response()->json(['data' => $this->maintenance->fitTyre($data, $request->user())], 201);
    }

    public function removeTyre(Request $request, FleetTyre $tyre): JsonResponse
    {
        $data = $request->validate([
            'removed_date' => ['nullable', 'date', 'before_or_equal:today'],
            'removed_odometer' => ['nullable', 'numeric', 'min:0'],
            'removal_reason' => ['required', 'string', 'max:255'],
        ]);

        return response()->json(['data' => $this->maintenance->removeTyre($tyre, $data, $request->user())]);
    }

    /* ------------------------------------------------------------ downtime */

    public function downtimes(Request $request): JsonResponse
    {
        $rows = FleetDowntime::query()->with('vehicle:id,registration_number')
            ->when($request->query('vehicle_id'), fn ($q, $v) => $q->where('vehicle_id', $v))
            ->when($request->query('open'), fn ($q) => $q->whereNull('ended_at'))
            ->latest('started_at')->limit(200)->get()
            ->map(fn ($d) => [...$d->toArray(), 'hours' => $d->hours()]);

        return response()->json(['data' => $rows]);
    }

    public function storeDowntime(Request $request): JsonResponse
    {
        $company = $this->tenant->id();
        $data = $request->validate([
            'vehicle_id' => ['required', 'integer', Rule::exists('fleet_vehicles', 'id')->where('company_id', $company)],
            'reason' => ['required', Rule::in(FleetDowntime::REASONS)],
            'description' => ['nullable', 'string', 'max:255'],
            'started_at' => ['nullable', 'date', 'before_or_equal:now'],
            'service_record_id' => ['nullable', 'integer', Rule::exists('fleet_service_records', 'id')->where('company_id', $company)],
        ]);

        return response()->json(['data' => $this->maintenance->startDowntime($data, $request->user())], 201);
    }

    public function endDowntime(Request $request, FleetDowntime $downtime): JsonResponse
    {
        $at = $request->validate(['ended_at' => ['nullable', 'date', 'before_or_equal:now']])['ended_at'] ?? null;

        return response()->json(['data' => $this->maintenance->endDowntime($downtime, $at, $request->user())]);
    }

    /* ------------------------------------------------------------ rules */

    /** @return array<string, mixed> */
    private function scheduleRules(Request $request): array
    {
        $data = $request->validate([
            'vehicle_id' => ['required', 'integer', Rule::exists('fleet_vehicles', 'id')->where('company_id', $this->tenant->id())],
            'title' => ['required', 'string', 'max:120'],
            'interval_km' => ['nullable', 'integer', 'min:1'],
            'interval_days' => ['nullable', 'integer', 'min:1'],
            'last_done_odometer' => ['nullable', 'numeric', 'min:0'],
            'last_done_date' => ['nullable', 'date'],
            'is_active' => ['boolean'],
        ]);

        if (empty($data['interval_km']) && empty($data['interval_days'])) {
            throw new RuntimeException('Give the interval in km, in days, or both.');
        }

        return $data;
    }

    /** @return array<string, mixed> */
    private function serviceRules(Request $request): array
    {
        $company = $this->tenant->id();

        return $request->validate([
            'vehicle_id' => ['required', 'integer', Rule::exists('fleet_vehicles', 'id')->where('company_id', $company)],
            'schedule_id' => ['nullable', 'integer', Rule::exists('fleet_maintenance_schedules', 'id')->where('company_id', $company)],
            'service_date' => ['required', 'date', 'before_or_equal:today'],
            'odometer' => ['nullable', 'numeric', 'min:0'],
            'work_done' => ['required', 'string', 'max:1000'],
            'cost' => ['nullable', 'numeric', 'min:0'],
            'supplier_id' => ['nullable', 'integer', Rule::exists('suppliers', 'id')->where('company_id', $company)],
            'account_id' => ['nullable', 'integer', Rule::exists('accounts', 'id')->where('company_id', $company)],
            'invoice_number' => ['nullable', 'string', 'max:60'],
        ]);
    }
}
