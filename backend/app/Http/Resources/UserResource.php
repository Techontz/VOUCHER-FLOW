<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class UserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'company_id' => $this->company_id,
            'name' => $this->name,
            'initials' => $this->initials(),
            'email' => $this->email,
            'phone' => $this->phone,
            'role' => $this->role,
            'role_label' => $this->roleLabel(),
            'employee_code' => $this->employee_code,
            'job_title' => $this->job_title,
            'status' => $this->status,
            'locale' => $this->locale,
            'theme' => $this->theme,
            'department_id' => $this->department_id,
            'department' => $this->whenLoaded('department', fn () => [
                'id' => $this->department?->id,
                'name' => $this->department?->name,
            ]),
            'avatar_url' => $this->avatar_path ? asset('storage/'.$this->avatar_path) : null,
            'has_signature' => (bool) $this->signature_data,
            'signature_updated_at' => $this->signature_updated_at?->toIso8601String(),
            'two_factor_enabled' => (bool) $this->two_factor_enabled,
            'last_login_at' => $this->last_login_at?->toIso8601String(),
            'joined_at' => $this->created_at?->toIso8601String(),
            'voucher_count' => $this->whenCounted('vouchers'),
        ];
    }

    private function roleLabel(): string
    {
        return match ($this->role) {
            'super_admin' => 'Super Admin',
            'company_admin' => 'Company Administrator',
            'employee' => 'Employee',
            'hod' => 'Head of Department',
            'manager' => 'Manager',
            'finance' => 'Finance',
            'director' => 'Director',
            default => ucfirst((string) $this->role),
        };
    }
}
