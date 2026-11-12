<?php

namespace App\Http\Resources\Erp\Hr;

use App\Models\Erp\Hr\Separation;
use App\Services\Erp\Hr\HrAccess;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * An exit with its clearance checklist. Final dues are salary data.
 *
 * @mixin Separation
 */
class SeparationResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'employee_id' => $this->employee_id,
            'employee' => $this->whenLoaded('employee', fn () => [
                'id' => $this->employee->id, 'full_name' => $this->employee->full_name,
                'employee_number' => $this->employee->employee_number, 'job_title' => $this->employee->job_title,
                'status' => $this->employee->status,
            ]),
            'type' => $this->type,
            'notice_date' => $this->notice_date?->toDateString(),
            'last_working_day' => $this->last_working_day?->toDateString(),
            'reason' => $this->reason,
            'status' => $this->status,
            'leave_days_payable' => (float) $this->leave_days_payable,
            'completed_at' => $this->completed_at,
            'items' => $this->whenLoaded('items', fn () => $this->items->map(fn ($i) => [
                'id' => $i->id, 'area' => $i->area, 'item' => $i->item, 'note' => $i->note,
                'cleared_at' => $i->cleared_at, 'cleared_by' => $i->clearer?->name,
            ])->values()),
            $this->mergeWhen(HrAccess::seesSalary($request->user()), fn () => [
                'leave_pay' => (float) $this->leave_pay,
                'other_dues' => (float) $this->other_dues,
                'outstanding_loans' => (float) $this->outstanding_loans,
                'final_dues' => (float) $this->final_dues,
            ]),
        ];
    }
}
