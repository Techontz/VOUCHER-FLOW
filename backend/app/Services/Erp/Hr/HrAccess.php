<?php

namespace App\Services\Erp\Hr;

use App\Models\Department;
use App\Models\Erp\Hr\Employee;
use App\Models\User;

/**
 * Who may see what inside HR, beyond the route's permission: salary and
 * disciplinary data are field-level, and a department head's reach stops at
 * the departments they lead.
 */
class HrAccess
{
    public static function seesSalary(?User $user): bool
    {
        return (bool) $user?->hasPermission('hr.salary');
    }

    public static function seesDiscipline(?User $user): bool
    {
        return (bool) $user?->hasPermission('hr.discipline');
    }

    /** Anyone who works on payroll sees what payroll pays; that is the job. */
    public static function worksOnPayroll(?User $user): bool
    {
        return $user !== null && collect(['hr.payroll.prepare', 'hr.payroll.authorise', 'hr.payroll.post'])
            ->contains(fn ($p) => $user->hasPermission($p));
    }

    /** @return list<int> */
    public static function ledDepartmentIds(User $user): array
    {
        return Department::query()
            ->where(fn ($q) => $q->where('hod_user_id', $user->id)->orWhere('manager_user_id', $user->id))
            ->pluck('id')->map(fn ($id) => (int) $id)->all();
    }

    public static function employeeFor(User $user): ?Employee
    {
        return Employee::query()->where('user_id', $user->id)->first();
    }

    /**
     * The employees a person may act for as a leave approver or team lead:
     * everyone for HR, otherwise their departments and their direct reports.
     *
     * @return list<int>|null null means no limit
     */
    public static function teamEmployeeIds(User $user): ?array
    {
        if ($user->hasPermission('hr.manage')) {
            return null;
        }

        $self = self::employeeFor($user);
        $departments = self::ledDepartmentIds($user);

        return Employee::query()
            ->where(function ($q) use ($departments, $self) {
                $q->whereIn('department_id', $departments ?: [0]);
                if ($self) {
                    $q->orWhere('manager_id', $self->id);
                }
            })
            ->pluck('id')->map(fn ($id) => (int) $id)->all();
    }
}
