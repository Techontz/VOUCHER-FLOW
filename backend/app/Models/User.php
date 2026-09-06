<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable, SoftDeletes;

    public const ROLE_SUPER_ADMIN = 'super_admin';

    public const ROLE_COMPANY_ADMIN = 'company_admin';

    public const ROLE_EMPLOYEE = 'employee';

    public const ROLE_HOD = 'hod';

    public const ROLE_MANAGER = 'manager';

    public const ROLE_FINANCE = 'finance';

    public const ROLE_DIRECTOR = 'director';

    /** Roles that may act on an approval step. */
    public const APPROVER_ROLES = [
        self::ROLE_HOD, self::ROLE_MANAGER, self::ROLE_FINANCE, self::ROLE_DIRECTOR,
    ];

    protected $guarded = ['id'];

    protected $hidden = ['password', 'remember_token', 'invitation_token'];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'signature_updated_at' => 'datetime',
            'two_factor_enabled' => 'boolean',
            'last_login_at' => 'datetime',
            'invited_at' => 'datetime',
        ];
    }

    // The tenant scope is deliberately NOT applied to User: authentication has to
    // find the account before a tenant can be resolved. Every tenant-facing query
    // goes through scopeForTenant() below instead.
    public function company(): BelongsTo
    {
        return $this->belongsTo(Company::class);
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function vouchers(): HasMany
    {
        return $this->hasMany(Voucher::class, 'requester_id');
    }

    public function headedDepartments(): HasMany
    {
        return $this->hasMany(Department::class, 'hod_user_id');
    }

    public function managedDepartments(): HasMany
    {
        return $this->hasMany(Department::class, 'manager_user_id');
    }

    public function notifications(): HasMany
    {
        return $this->hasMany(AppNotification::class);
    }

    public function scopeForTenant($query, ?int $companyId)
    {
        return $query->where('company_id', $companyId);
    }

    public function isSuperAdmin(): bool
    {
        return $this->role === self::ROLE_SUPER_ADMIN;
    }

    public function isCompanyAdmin(): bool
    {
        return $this->role === self::ROLE_COMPANY_ADMIN;
    }

    /** Company admins administer their own tenant; super admins administer all. */
    public function isAdmin(): bool
    {
        return $this->isSuperAdmin() || $this->isCompanyAdmin();
    }

    public function isApprover(): bool
    {
        return in_array($this->role, self::APPROVER_ROLES, true);
    }

    public function isActive(): bool
    {
        return $this->status === 'active';
    }

    public function initials(): string
    {
        return collect(preg_split('/\s+/', trim((string) $this->name)))
            ->filter()
            ->take(2)
            ->map(fn ($word) => mb_strtoupper(mb_substr($word, 0, 1)))
            ->implode('');
    }
}
