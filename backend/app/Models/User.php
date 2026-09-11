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

    public const ROLE_CEO = 'ceo';

    public const ROLE_CASHIER = 'cashier';

    /** Roles that may act on an approval step. */
    public const APPROVER_ROLES = [
        self::ROLE_HOD, self::ROLE_MANAGER, self::ROLE_CEO,
        self::ROLE_FINANCE, self::ROLE_CASHIER, self::ROLE_DIRECTOR,
    ];

    /**
     * The vocabulary a company admin may assign inside their own tenant.
     *
     * Kept here rather than repeated in each controller's validation rule: it
     * had drifted across six `Rule::in` lists, and a role added to one of them
     * was silently rejected by the others. When per-company role definitions
     * arrive this is the single place that has to start reading from the tenant.
     */
    public const ASSIGNABLE_ROLES = [
        self::ROLE_COMPANY_ADMIN, self::ROLE_EMPLOYEE, self::ROLE_HOD,
        self::ROLE_CEO, self::ROLE_MANAGER, self::ROLE_CASHIER,
        self::ROLE_FINANCE, self::ROLE_DIRECTOR,
    ];

    /** Everything above, plus the platform role no tenant may grant. */
    public const ALL_ROLES = [self::ROLE_SUPER_ADMIN, ...self::ASSIGNABLE_ROLES];

    /** Roles whose workflow step releases money. */
    public const PAYING_ROLES = [self::ROLE_CASHIER, self::ROLE_FINANCE];

    /**
     * Roles that act for the whole company rather than for one department.
     *
     * An HOD's authority is bounded by the departments they head, so a bare
     * role match must never widen them. These roles have no such boundary — a
     * CEO approves across the company and a cashier pays across it — so for
     * them a role-matched step is authority enough.
     */
    public const COMPANY_WIDE_ROLES = [
        self::ROLE_CEO, self::ROLE_DIRECTOR, self::ROLE_FINANCE, self::ROLE_CASHIER,
    ];

    public function actsCompanyWide(): bool
    {
        return in_array($this->role, self::COMPANY_WIDE_ROLES, true);
    }

    public static function roleLabel(string $role): string
    {
        return match ($role) {
            self::ROLE_SUPER_ADMIN => 'Platform Super Admin',
            self::ROLE_COMPANY_ADMIN => 'Company Administrator',
            self::ROLE_EMPLOYEE => 'Employee',
            self::ROLE_HOD => 'Head of Department',
            self::ROLE_CEO => 'CEO / Managing Director',
            self::ROLE_MANAGER => 'Manager',
            self::ROLE_CASHIER => 'Cashier',
            self::ROLE_FINANCE => 'Finance',
            self::ROLE_DIRECTOR => 'Director',
            default => ucfirst(str_replace('_', ' ', $role)),
        };
    }

    /** Whether this user's step in a workflow may release money. */
    public function canPay(): bool
    {
        return in_array($this->role, self::PAYING_ROLES, true);
    }

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
