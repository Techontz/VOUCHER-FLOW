<?php

namespace App\Services\Erp\Hr;

use App\Models\Erp\Hr\Contract;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\HrSetting;
use App\Models\Erp\Hr\LeaveType;
use App\Models\Erp\Hr\Loan;
use App\Models\Erp\Hr\Separation;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Exit and clearance. An exit opens with a checklist across departments and
 * an estimate of final dues (untaken annual leave paid out, other dues, less
 * loans still owed). It completes only when every item is cleared; then the
 * person is marked exited, their contract ends and their sign-in is suspended.
 */
class SeparationService
{
    public function __construct(
        private readonly LeaveService $leave,
        private readonly AuditLogger $audit,
    ) {}

    /** @param  array<string, mixed>  $data */
    public function open(Employee $employee, array $data, User $actor): Separation
    {
        return DB::transaction(function () use ($employee, $data, $actor) {
            if ($employee->status === Employee::STATUS_EXITED) {
                throw new RuntimeException("{$employee->full_name} has already exited.");
            }

            if (Separation::query()->where('employee_id', $employee->id)->where('status', 'in_progress')->exists()) {
                throw new RuntimeException("An exit for {$employee->full_name} is already in progress.");
            }

            if (Carbon::parse($data['last_working_day'])->lt(Carbon::parse($data['notice_date']))) {
                throw new RuntimeException('The last working day cannot be before the notice date.');
            }

            $separation = Separation::create([
                'employee_id' => $employee->id,
                'type' => $data['type'],
                'notice_date' => $data['notice_date'],
                'last_working_day' => $data['last_working_day'],
                'reason' => $data['reason'] ?? null,
                'other_dues' => $data['other_dues'] ?? 0,
                'status' => 'in_progress',
                'created_by' => $actor->id,
            ]);

            foreach (Separation::CLEARANCE as [$area, $item]) {
                $separation->items()->create([
                    'area' => $area, 'item' => $item,
                    'department_id' => $area === 'Line department' ? $employee->department_id : null,
                ]);
            }

            $this->computeDues($separation);
            $this->audit->log('hr.exit.opened', "Opened {$separation->type} exit for {$employee->full_name}, last day {$separation->last_working_day->toDateString()}", $separation, actor: $actor);

            return $separation->fresh(['items', 'employee']);
        });
    }

    /** @param  array<string, mixed>  $data */
    public function update(Separation $separation, array $data, User $actor): Separation
    {
        $this->assertOpen($separation);
        $separation->update($data);
        $this->computeDues($separation);
        $this->audit->log('hr.exit.updated', "Updated exit of {$separation->employee->full_name}", $separation, actor: $actor);

        return $separation->fresh(['items', 'employee']);
    }

    public function clear(Separation $separation, int $itemId, User $actor, ?string $note = null, bool $cleared = true): Separation
    {
        $this->assertOpen($separation);
        $item = $separation->items()->findOrFail($itemId);
        $item->update($cleared
            ? ['cleared_by' => $actor->id, 'cleared_at' => now(), 'note' => $note]
            : ['cleared_by' => null, 'cleared_at' => null, 'note' => $note]);
        $this->audit->log('hr.exit.cleared', ($cleared ? 'Cleared' : 'Reopened')." {$item->area}: {$item->item} for {$separation->employee->full_name}", $separation, actor: $actor);

        return $separation->fresh(['items.clearer', 'employee']);
    }

    public function complete(Separation $separation, User $actor): Separation
    {
        return DB::transaction(function () use ($separation, $actor) {
            $locked = Separation::query()->whereKey($separation->id)->lockForUpdate()->firstOrFail();
            $this->assertOpen($locked);

            $pending = $locked->items()->whereNull('cleared_at')->count();
            if ($pending > 0) {
                throw new RuntimeException("{$pending} clearance item(s) are still outstanding.");
            }

            $this->computeDues($locked);
            $employee = $locked->employee;
            $last = $locked->last_working_day;

            $employee->update(['status' => Employee::STATUS_EXITED, 'exit_date' => $last->toDateString()]);
            $employee->contracts()->where('status', Contract::STATUS_ACTIVE)->get()->each(fn (Contract $c) => $c->update([
                'status' => Contract::STATUS_ENDED,
                'end_date' => $c->end_date && $c->end_date->lt($last) ? $c->end_date : $last->toDateString(),
            ]));

            if ($employee->user_id && ($user = User::query()->find($employee->user_id)) && ! $user->isCompanyAdmin()) {
                $user->forceFill(['status' => 'suspended'])->save();
                $user->tokens()->delete();
            }

            $locked->update(['status' => 'completed', 'completed_by' => $actor->id, 'completed_at' => now()]);
            $this->audit->log('hr.exit.completed', "Completed exit of {$employee->full_name}; final dues ".number_format((float) $locked->final_dues, 2), $locked, actor: $actor);

            return $locked->fresh(['items', 'employee']);
        });
    }

    /** Untaken annual leave paid out at the daily rate, plus other dues, less loans still owed. */
    public function computeDues(Separation $separation): void
    {
        $employee = $separation->employee;
        $last = $separation->last_working_day;
        $this->leave->ensureTypes();
        $annual = LeaveType::query()->where('code', 'annual')->first();
        $days = 0.0;

        if ($annual) {
            $balance = $this->leave->balance($employee, $annual, $last->year);
            $days = max(0, (float) $this->leave->available($balance, $last->copy()));
        }

        $contract = $employee->contracts()->orderByDesc('start_date')->first();
        $daily = $contract ? (float) $contract->basic_salary / max(1, (float) HrSetting::current()->working_days_per_month) : 0;
        $leavePay = round($days * $daily, 2);
        $loans = round((float) Loan::query()->where('employee_id', $employee->id)->where('status', Loan::STATUS_ACTIVE)->sum('balance'), 2);

        $separation->update([
            'leave_days_payable' => $days,
            'leave_pay' => $leavePay,
            'outstanding_loans' => $loans,
            'final_dues' => round($leavePay + (float) $separation->other_dues - $loans, 2),
        ]);
    }

    private function assertOpen(Separation $separation): void
    {
        if ($separation->status !== 'in_progress') {
            throw new RuntimeException('This exit is complete and cannot change.');
        }
    }
}
