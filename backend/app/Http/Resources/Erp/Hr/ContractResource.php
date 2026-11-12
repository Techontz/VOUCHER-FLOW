<?php

namespace App\Http\Resources\Erp\Hr;

use App\Models\Erp\Hr\Contract;
use App\Services\Erp\Hr\HrAccess;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A contract. Its pay is salary data: without hr.salary the figures are not
 * in the response at all, not merely hidden on screen.
 *
 * @mixin Contract
 */
class ContractResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $salary = HrAccess::seesSalary($request->user());

        return [
            'id' => $this->id,
            'employee_id' => $this->employee_id,
            'type' => $this->type,
            'start_date' => $this->start_date?->toDateString(),
            'end_date' => $this->end_date?->toDateString(),
            'status' => $this->status,
            'notes' => $this->notes,
            'created_at' => $this->created_at,
            $this->mergeWhen($salary, fn () => [
                'basic_salary' => (float) $this->basic_salary,
                'housing_allowance' => (float) $this->housing_allowance,
                'transport_allowance' => (float) $this->transport_allowance,
                'other_allowance' => (float) $this->other_allowance,
                'gross_salary' => round((float) $this->basic_salary + $this->allowances(), 2),
            ]),
        ];
    }
}
