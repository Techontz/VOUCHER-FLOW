<?php

namespace App\Services\Erp\Hr;

use App\Models\Erp\Hr\Applicant;
use App\Models\Erp\Hr\Contract;
use App\Models\Erp\Hr\Employee;
use App\Models\Erp\Hr\Movement;
use App\Models\Erp\Hr\OnboardingTask;
use App\Models\Erp\Hr\Vacancy;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\Erp\DocumentNumberer;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Employee records: hiring (directly or from an applicant), contracts with
 * history, and transfers and promotions. A department or title changes only
 * through a movement, so the history is never lost; the linked user's own
 * department and title follow, so VouchFlow routes their vouchers correctly.
 */
class EmployeeService
{
    /** Profile fields anyone with hr.manage may set directly. */
    public const PROFILE = [
        'full_name', 'email', 'phone', 'national_id', 'tin', 'nssf_number', 'date_of_birth', 'gender', 'address',
        'next_of_kin_name', 'next_of_kin_phone', 'next_of_kin_relation', 'employment_type', 'manager_id', 'shift_id',
        'hire_date', 'probation_end', 'heslb_beneficiary',
    ];

    /** Salary-adjacent fields that need hr.salary to set. */
    public const BANK = ['bank_name', 'bank_account_number'];

    public function __construct(
        private readonly DocumentNumberer $numbers,
        private readonly AuditLogger $audit,
    ) {}

    /**
     * @param  array<string, mixed>  $data
     * @param  array<string, mixed>|null  $contract
     */
    public function create(array $data, ?array $contract, User $actor): Employee
    {
        return DB::transaction(function () use ($data, $contract, $actor) {
            if (! empty($data['user_id'])) {
                $user = User::query()->forTenant($actor->company_id)->find($data['user_id'])
                    ?? throw new RuntimeException('That user does not belong to this company.');

                if (Employee::query()->where('user_id', $user->id)->exists()) {
                    throw new RuntimeException("{$user->name} already has an employee record.");
                }
            }

            $employee = Employee::create([
                ...array_intersect_key($data, array_flip([...self::PROFILE, ...self::BANK, 'user_id', 'job_title', 'grade', 'department_id'])),
                'employee_number' => ($data['employee_number'] ?? null) ?: $this->numbers->next('EMP'),
                'status' => Employee::STATUS_ACTIVE,
                'created_by' => $actor->id,
            ]);

            if ($contract) {
                $this->newContract($employee, $contract, $actor, audit: false);
            }

            foreach (OnboardingTask::DEFAULTS as $i => $title) {
                $employee->onboardingTasks()->create(['title' => $title, 'sort' => $i + 1]);
            }

            $this->syncUser($employee);
            $this->audit->log('hr.employee.created', "Added employee {$employee->employee_number} {$employee->full_name}", $employee, actor: $actor);

            return $employee;
        });
    }

    /** @param  array<string, mixed>  $data */
    public function update(Employee $employee, array $data, User $actor): Employee
    {
        $before = $employee->only(array_keys($data));

        if (isset($data['status']) && $data['status'] === Employee::STATUS_EXITED) {
            throw new RuntimeException('An employee leaves through an exit, so their clearance and final dues are recorded.');
        }

        if (isset($data['status']) && $employee->status === Employee::STATUS_EXITED) {
            throw new RuntimeException("{$employee->full_name} has exited and cannot be reactivated here.");
        }

        if (! empty($data['manager_id']) && (int) $data['manager_id'] === $employee->id) {
            throw new RuntimeException('A person cannot be their own manager.');
        }

        $employee->update($data);
        $this->syncUser($employee);
        $this->audit->log('hr.employee.updated', "Updated employee {$employee->employee_number} {$employee->full_name}", $employee, $before, $employee->only(array_keys($data)), actor: $actor);

        return $employee;
    }

    /**
     * Starts a new contract. The current one is superseded and ends the day
     * before, so exactly one contract is active and the old terms stay on file.
     *
     * @param  array<string, mixed>  $data
     */
    public function newContract(Employee $employee, array $data, User $actor, bool $audit = true): Contract
    {
        return DB::transaction(function () use ($employee, $data, $actor, $audit) {
            $start = Carbon::parse($data['start_date']);

            if (! empty($data['end_date']) && Carbon::parse($data['end_date'])->lt($start)) {
                throw new RuntimeException('A contract cannot end before it starts.');
            }

            foreach ($employee->contracts()->where('status', Contract::STATUS_ACTIVE)->lockForUpdate()->get() as $current) {
                if ($current->start_date->gte($start)) {
                    throw new RuntimeException('A new contract must start after the current one, which began on '.$current->start_date->toDateString().'.');
                }

                $end = $start->copy()->subDay();
                $current->update([
                    'status' => Contract::STATUS_SUPERSEDED,
                    'end_date' => $current->end_date && $current->end_date->lt($end) ? $current->end_date : $end,
                ]);
            }

            $contract = $employee->contracts()->create([
                'type' => $data['type'] ?? 'permanent',
                'start_date' => $start->toDateString(),
                'end_date' => $data['end_date'] ?? null,
                'basic_salary' => $data['basic_salary'],
                'housing_allowance' => $data['housing_allowance'] ?? 0,
                'transport_allowance' => $data['transport_allowance'] ?? 0,
                'other_allowance' => $data['other_allowance'] ?? 0,
                'status' => Contract::STATUS_ACTIVE,
                'notes' => $data['notes'] ?? null,
                'created_by' => $actor->id,
            ]);

            if ($audit) {
                $this->audit->log('hr.contract.created', "New {$contract->type} contract for {$employee->full_name} from {$contract->start_date->toDateString()}", $contract, actor: $actor);
            }

            return $contract;
        });
    }

    /** @param  array<string, mixed>  $data */
    public function move(Employee $employee, array $data, User $actor): Movement
    {
        return DB::transaction(function () use ($employee, $data, $actor) {
            $to = [
                'department_id' => $data['to_department_id'] ?? $employee->department_id,
                'job_title' => $data['to_job_title'] ?? $employee->job_title,
                'grade' => $data['to_grade'] ?? $employee->grade,
            ];

            if ($to['department_id'] === $employee->department_id && $to['job_title'] === $employee->job_title && $to['grade'] === $employee->grade) {
                throw new RuntimeException('Nothing changes: choose a new department, title or grade.');
            }

            $movement = $employee->movements()->create([
                'type' => $data['type'],
                'effective_date' => $data['effective_date'],
                'from_department_id' => $employee->department_id,
                'to_department_id' => $to['department_id'],
                'from_job_title' => $employee->job_title,
                'to_job_title' => $to['job_title'],
                'from_grade' => $employee->grade,
                'to_grade' => $to['grade'],
                'reason' => $data['reason'] ?? null,
                'created_by' => $actor->id,
            ]);

            $employee->update($to);
            $this->syncUser($employee);
            $this->audit->log("hr.employee.{$movement->type}", ucfirst($movement->type)." of {$employee->full_name}", $employee, actor: $actor);

            return $movement;
        });
    }

    /**
     * Turns a hired applicant into an employee, with a contract and the
     * onboarding checklist, and fills the vacancy once its places are taken.
     *
     * @param  array<string, mixed>  $data
     * @param  array<string, mixed>|null  $contract
     */
    public function hire(Applicant $applicant, array $data, ?array $contract, User $actor): Employee
    {
        return DB::transaction(function () use ($applicant, $data, $contract, $actor) {
            $locked = Applicant::query()->with('vacancy')->whereKey($applicant->id)->lockForUpdate()->firstOrFail();

            if ($locked->employee_id) {
                throw new RuntimeException("{$locked->name} has already been hired.");
            }

            if ($locked->stage === 'rejected') {
                throw new RuntimeException("{$locked->name} was rejected and cannot be hired.");
            }

            $employee = $this->create([
                'full_name' => $locked->name,
                'email' => $locked->email,
                'phone' => $locked->phone,
                'job_title' => $locked->vacancy->title,
                'department_id' => $locked->vacancy->department_id,
                'employment_type' => $locked->vacancy->employment_type,
                ...$data,
            ], $contract, $actor);

            $locked->update(['stage' => 'hired', 'employee_id' => $employee->id]);

            $vacancy = $locked->vacancy;
            if ($vacancy->applicants()->where('stage', 'hired')->count() >= $vacancy->positions) {
                $vacancy->update(['status' => 'filled']);
            }

            $this->audit->log('hr.applicant.hired', "Hired {$locked->name} for {$vacancy->title}", $locked, actor: $actor);

            return $employee;
        });
    }

    /** Keeps the linked sign-in's department and title in step with HR. */
    private function syncUser(Employee $employee): void
    {
        if ($employee->user_id && ($user = User::query()->find($employee->user_id))) {
            $user->forceFill([
                'department_id' => $employee->department_id,
                'job_title' => $employee->job_title ?? $user->job_title,
                'employee_code' => $user->employee_code ?: $employee->employee_number,
            ])->save();
        }
    }
}
