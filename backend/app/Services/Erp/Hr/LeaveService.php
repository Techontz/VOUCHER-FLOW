<?php

namespace App\Services\Erp\Hr;

use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\LeaveBalance;
use App\Models\Erp\Hr\LeaveRequest;
use App\Models\Erp\Hr\LeaveType;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Leave from request to balance.
 *
 * A balance is per person, per kind of leave, per year. Days are taken from it
 * only when a request is approved, under a row lock, and given back when an
 * approved request is cancelled, so the balance is always the entitlement less
 * exactly the approved days. Annual leave accrues month by month: what is
 * available is what has been earned so far this year.
 */
class LeaveService
{
    /** Tanzanian statutory defaults (Employment and Labour Relations Act). */
    public const DEFAULT_TYPES = [
        ['code' => 'annual', 'name' => 'Annual leave', 'days_per_year' => 28, 'paid' => true, 'accrues_monthly' => true, 'counting' => 'working'],
        ['code' => 'sick', 'name' => 'Sick leave', 'days_per_year' => 63, 'paid' => true, 'accrues_monthly' => false, 'counting' => 'working'],
        ['code' => 'maternity', 'name' => 'Maternity leave', 'days_per_year' => 84, 'paid' => true, 'accrues_monthly' => false, 'counting' => 'calendar'],
        ['code' => 'paternity', 'name' => 'Paternity leave', 'days_per_year' => 3, 'paid' => true, 'accrues_monthly' => false, 'counting' => 'working'],
        ['code' => 'compassionate', 'name' => 'Compassionate leave', 'days_per_year' => 4, 'paid' => true, 'accrues_monthly' => false, 'counting' => 'working'],
        ['code' => 'unpaid', 'name' => 'Unpaid leave', 'days_per_year' => null, 'paid' => false, 'accrues_monthly' => false, 'counting' => 'working'],
    ];

    public function __construct(private readonly AuditLogger $audit) {}

    public function ensureTypes(): void
    {
        if (LeaveType::query()->exists()) {
            return;
        }

        foreach (self::DEFAULT_TYPES as $type) {
            LeaveType::create($type);
        }
    }

    /** The days a request draws, by the type's counting rule. */
    public static function countDays(LeaveType $type, Carbon|string $start, Carbon|string $end): float
    {
        $from = Carbon::parse($start)->startOfDay();
        $to = Carbon::parse($end)->startOfDay();
        $days = 0;

        for ($day = $from->copy(); $day->lte($to); $day->addDay()) {
            if ($type->counting === 'calendar' || ! $day->isWeekend()) {
                $days++;
            }
        }

        return (float) $days;
    }

    public function balance(Employee $employee, LeaveType $type, int $year, bool $lock = false): LeaveBalance
    {
        $find = fn () => LeaveBalance::query()
            ->where('employee_id', $employee->id)->where('leave_type_id', $type->id)->where('year', $year)
            ->when($lock, fn ($q) => $q->lockForUpdate())
            ->first();

        if ($balance = $find()) {
            return $balance;
        }

        LeaveBalance::query()->insertOrIgnore([
            'company_id' => $employee->company_id, 'employee_id' => $employee->id, 'leave_type_id' => $type->id,
            'year' => $year, 'entitled' => $this->entitlement($employee, $type, $year),
            'created_at' => now(), 'updated_at' => now(),
        ]);

        return $find();
    }

    /** A full year's entitlement, pro rata for monthly-accruing leave in the year someone joins. */
    public function entitlement(Employee $employee, LeaveType $type, int $year): float
    {
        if (! $type->isLimited()) {
            return 0.0;
        }

        $days = (float) $type->days_per_year;

        if ($type->accrues_monthly && $employee->hire_date && $employee->hire_date->year === $year) {
            return round($days * (13 - $employee->hire_date->month) / 12, 2);
        }

        return $days;
    }

    /** What a monthly-accruing balance has earned by a date; the whole entitlement otherwise. */
    public function accrued(LeaveBalance $balance, ?Carbon $asOf = null): float
    {
        $type = $balance->leaveType;
        $entitled = (float) $balance->entitled;

        if (! $type->accrues_monthly) {
            return $entitled;
        }

        $asOf ??= now();
        $hire = $balance->employee?->hire_date;
        $startMonth = $hire && $hire->year === $balance->year ? $hire->month : 1;
        $months = 13 - $startMonth;
        $elapsed = match (true) {
            $balance->year < $asOf->year => $months,
            $balance->year > $asOf->year => 0,
            default => max(0, min($months, $asOf->month - $startMonth + 1)),
        };

        return round($entitled * $elapsed / max(1, $months), 2);
    }

    /** Days still available, or null for leave without a limit. */
    public function available(LeaveBalance $balance, ?Carbon $asOf = null): ?float
    {
        if (! $balance->leaveType->isLimited()) {
            return null;
        }

        return round($this->accrued($balance, $asOf) + (float) $balance->carried_forward + (float) $balance->adjustment - (float) $balance->taken, 2);
    }

    /** @return array<string, mixed> */
    public function describe(LeaveBalance $balance): array
    {
        $balance->loadMissing('leaveType', 'employee');

        return [
            'id' => $balance->id,
            'employee_id' => $balance->employee_id,
            'leave_type_id' => $balance->leave_type_id,
            'leave_type' => ['id' => $balance->leaveType->id, 'code' => $balance->leaveType->code, 'name' => $balance->leaveType->name, 'paid' => $balance->leaveType->paid],
            'year' => $balance->year,
            'entitled' => (float) $balance->entitled,
            'accrued' => $this->accrued($balance),
            'carried_forward' => (float) $balance->carried_forward,
            'adjustment' => (float) $balance->adjustment,
            'taken' => (float) $balance->taken,
            'available' => $this->available($balance),
            'limited' => $balance->leaveType->isLimited(),
        ];
    }

    /** @return list<array<string, mixed>> every active type's balance for a year */
    public function balancesFor(Employee $employee, int $year): array
    {
        $this->ensureTypes();

        return LeaveType::query()->where('is_active', true)->orderBy('id')->get()
            ->map(fn (LeaveType $type) => $this->describe($this->balance($employee, $type, $year)))
            ->all();
    }

    /** @param  array{leave_type_id: int, start_date: string, end_date: string, reason?: ?string}  $data */
    public function request(Employee $employee, array $data, User $actor): LeaveRequest
    {
        return DB::transaction(function () use ($employee, $data, $actor) {
            if (! $employee->isActive()) {
                throw new RuntimeException("{$employee->full_name} is not an active employee.");
            }

            $type = LeaveType::query()->where('is_active', true)->findOrFail($data['leave_type_id']);
            $start = Carbon::parse($data['start_date']);
            $end = Carbon::parse($data['end_date']);

            if ($end->lt($start)) {
                throw new RuntimeException('The last day of leave cannot be before the first.');
            }

            if ($start->year !== $end->year) {
                throw new RuntimeException('Leave that crosses into a new year must be requested as two requests, one for each year.');
            }

            $days = self::countDays($type, $start, $end);

            if ($days <= 0) {
                throw new RuntimeException('Those dates fall on a weekend; there are no working days to take.');
            }

            $overlap = LeaveRequest::query()
                ->where('employee_id', $employee->id)
                ->whereIn('status', [LeaveRequest::STATUS_PENDING, LeaveRequest::STATUS_APPROVED])
                ->whereDate('start_date', '<=', $end)->whereDate('end_date', '>=', $start)
                ->exists();

            if ($overlap) {
                throw new RuntimeException('These dates overlap another pending or approved leave request.');
            }

            $this->assertAvailable($employee, $type, $start->year, $days);

            $request = LeaveRequest::create([
                'employee_id' => $employee->id,
                'leave_type_id' => $type->id,
                'start_date' => $start->toDateString(),
                'end_date' => $end->toDateString(),
                'days' => $days,
                'reason' => $data['reason'] ?? null,
                'status' => LeaveRequest::STATUS_PENDING,
                'requested_by' => $actor->id,
            ]);

            $this->audit->log('hr.leave.requested', "{$employee->full_name} requested {$days} days of {$type->name}", $request, actor: $actor);

            return $request->load('leaveType', 'employee');
        });
    }

    /** Whether this person may decide this request. */
    public function canDecide(User $user, LeaveRequest $request): bool
    {
        if (! $user->hasPermission('hr.leave.approve')) {
            return false;
        }

        $employee = $request->employee;

        if ($employee->user_id === $user->id) {
            return false;
        }

        $team = HrAccess::teamEmployeeIds($user);

        return $team === null || in_array($employee->id, $team, true);
    }

    public function approve(LeaveRequest $request, User $actor, ?string $note = null): LeaveRequest
    {
        return DB::transaction(function () use ($request, $actor, $note) {
            $locked = $this->lockPending($request, $actor, 'approved');
            $type = $locked->leaveType;

            $balance = $this->balance($locked->employee, $type, $locked->start_date->year, lock: true);
            $available = $this->available($balance);

            if ($available !== null && (float) $locked->days > $available) {
                throw new RuntimeException("Only {$available} days of {$type->name} are available; this request needs {$locked->days}.");
            }

            $balance->update(['taken' => round((float) $balance->taken + (float) $locked->days, 2)]);
            $locked->update([
                'status' => LeaveRequest::STATUS_APPROVED, 'decided_by' => $actor->id, 'decided_at' => now(), 'decision_note' => $note,
            ]);

            $this->audit->log('hr.leave.approved', "Approved {$locked->days} days of {$type->name} for {$locked->employee->full_name}", $locked, actor: $actor);

            return $locked->fresh(['leaveType', 'employee', 'decider']);
        });
    }

    public function reject(LeaveRequest $request, User $actor, string $note): LeaveRequest
    {
        return DB::transaction(function () use ($request, $actor, $note) {
            $locked = $this->lockPending($request, $actor, 'rejected');
            $locked->update([
                'status' => LeaveRequest::STATUS_REJECTED, 'decided_by' => $actor->id, 'decided_at' => now(), 'decision_note' => $note,
            ]);

            $this->audit->log('hr.leave.rejected', "Rejected {$locked->leaveType->name} for {$locked->employee->full_name}: {$note}", $locked, actor: $actor);

            return $locked->fresh(['leaveType', 'employee', 'decider']);
        });
    }

    /**
     * Withdraws a request. Approved days go back to the balance. The person
     * themselves may cancel until the leave starts; HR may cancel at any time.
     */
    public function cancel(LeaveRequest $request, User $actor): LeaveRequest
    {
        return DB::transaction(function () use ($request, $actor) {
            $locked = LeaveRequest::query()->with('leaveType', 'employee')->whereKey($request->id)->lockForUpdate()->firstOrFail();
            $own = $locked->employee->user_id === $actor->id;
            $hr = $actor->hasPermission('hr.manage');

            if (! in_array($locked->status, [LeaveRequest::STATUS_PENDING, LeaveRequest::STATUS_APPROVED], true)) {
                throw new RuntimeException("This request is {$locked->status} and cannot be cancelled.");
            }

            if (! $hr && ! $own) {
                abort(403, 'Only the employee or HR may cancel this leave request.');
            }

            if (! $hr && $locked->status === LeaveRequest::STATUS_APPROVED && $locked->start_date->lte(today())) {
                throw new RuntimeException('This leave has already started. Ask HR to cancel it.');
            }

            if ($locked->status === LeaveRequest::STATUS_APPROVED) {
                $balance = $this->balance($locked->employee, $locked->leaveType, $locked->start_date->year, lock: true);
                $balance->update(['taken' => max(0, round((float) $balance->taken - (float) $locked->days, 2))]);
            }

            $locked->update(['status' => LeaveRequest::STATUS_CANCELLED, 'cancelled_by' => $actor->id, 'cancelled_at' => now()]);
            $this->audit->log('hr.leave.cancelled', "Cancelled {$locked->leaveType->name} for {$locked->employee->full_name}", $locked, actor: $actor);

            return $locked->fresh(['leaveType', 'employee']);
        });
    }

    /**
     * Unpaid leave days that fall inside a date range, per employee, for payroll.
     *
     * @return array<int, float>
     */
    public function unpaidDays(Carbon $from, Carbon $to): array
    {
        $days = [];

        LeaveRequest::query()->with('leaveType')
            ->where('status', LeaveRequest::STATUS_APPROVED)
            ->whereHas('leaveType', fn ($q) => $q->where('paid', false))
            ->whereDate('start_date', '<=', $to)->whereDate('end_date', '>=', $from)
            ->get()
            ->each(function (LeaveRequest $r) use (&$days, $from, $to) {
                $start = $r->start_date->max($from);
                $end = $r->end_date->min($to);
                $days[$r->employee_id] = ($days[$r->employee_id] ?? 0) + self::countDays($r->leaveType, $start, $end);
            });

        return $days;
    }

    private function assertAvailable(Employee $employee, LeaveType $type, int $year, float $days): void
    {
        $available = $this->available($this->balance($employee, $type, $year));

        if ($available !== null && $days > $available) {
            throw new RuntimeException("Only {$available} days of {$type->name} are available; this request needs {$days}.");
        }
    }

    private function lockPending(LeaveRequest $request, User $actor, string $verb): LeaveRequest
    {
        $locked = LeaveRequest::query()->with('leaveType', 'employee')->whereKey($request->id)->lockForUpdate()->firstOrFail();

        if ($locked->status !== LeaveRequest::STATUS_PENDING) {
            throw new RuntimeException("This request is already {$locked->status} and cannot be {$verb}.");
        }

        if ($locked->employee->user_id === $actor->id) {
            throw new RuntimeException('You cannot decide your own leave request.');
        }

        abort_unless($this->canDecide($actor, $locked), 403, 'You may decide leave only for your own department or direct reports.');

        return $locked;
    }
}
