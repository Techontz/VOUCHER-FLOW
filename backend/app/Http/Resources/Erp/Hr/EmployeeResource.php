<?php

namespace App\Http\Resources\Erp\Hr;

use App\Models\Erp\Hr\Employee;
use App\Services\Erp\Hr\HrAccess;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * An employee record. Bank details and pay appear only for holders of
 * hr.salary; nothing disciplinary is ever part of this resource.
 *
 * @mixin Employee
 */
class EmployeeResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $salary = HrAccess::seesSalary($request->user());

        return [
            'id' => $this->id,
            'employee_number' => $this->employee_number,
            'full_name' => $this->full_name,
            'email' => $this->email,
            'phone' => $this->phone,
            'national_id' => $this->national_id,
            'tin' => $this->tin,
            'nssf_number' => $this->nssf_number,
            'date_of_birth' => $this->date_of_birth?->toDateString(),
            'gender' => $this->gender,
            'address' => $this->address,
            'next_of_kin_name' => $this->next_of_kin_name,
            'next_of_kin_phone' => $this->next_of_kin_phone,
            'next_of_kin_relation' => $this->next_of_kin_relation,
            'employment_type' => $this->employment_type,
            'job_title' => $this->job_title,
            'grade' => $this->grade,
            'department_id' => $this->department_id,
            'department' => $this->whenLoaded('department', fn () => $this->department ? ['id' => $this->department->id, 'name' => $this->department->name] : null),
            'manager_id' => $this->manager_id,
            'manager' => $this->whenLoaded('manager', fn () => $this->manager ? ['id' => $this->manager->id, 'full_name' => $this->manager->full_name] : null),
            'shift_id' => $this->shift_id,
            'shift' => $this->whenLoaded('shift', fn () => $this->shift ? ['id' => $this->shift->id, 'name' => $this->shift->name] : null),
            'user_id' => $this->user_id,
            'user' => $this->whenLoaded('user', fn () => $this->user ? ['id' => $this->user->id, 'name' => $this->user->name, 'email' => $this->user->email, 'role' => $this->user->role] : null),
            'hire_date' => $this->hire_date?->toDateString(),
            'probation_end' => $this->probation_end?->toDateString(),
            'heslb_beneficiary' => $this->heslb_beneficiary,
            'status' => $this->status,
            'exit_date' => $this->exit_date?->toDateString(),
            'contract' => $this->whenLoaded('activeContract', fn () => $this->activeContract ? new ContractResource($this->activeContract) : null),
            $this->mergeWhen($salary, fn () => [
                'bank_name' => $this->bank_name,
                'bank_account_number' => $this->bank_account_number,
            ]),
            'salary_visible' => $salary,
        ];
    }
}
