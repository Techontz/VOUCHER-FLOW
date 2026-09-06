<?php

namespace App\Support;

use App\Models\Company;

/**
 * Holds the tenant the current request is operating inside.
 *
 * Every tenant-owned model applies {@see \App\Scopes\TenantScope}, which reads
 * this object. The scope fails closed: unless a tenant has been resolved, or the
 * request has been explicitly marked as platform-level (super admin), no rows are
 * returned at all. Isolation therefore does not depend on any controller
 * remembering to filter.
 */
class TenantContext
{
    protected ?Company $company = null;

    protected bool $platform = false;

    public function set(Company $company): void
    {
        $this->company = $company;
        $this->platform = false;
    }

    /** Marks the request as platform-level: the tenant scope is lifted. */
    public function asPlatform(): void
    {
        $this->company = null;
        $this->platform = true;
    }

    public function clear(): void
    {
        $this->company = null;
        $this->platform = false;
    }

    public function company(): ?Company
    {
        return $this->company;
    }

    public function id(): ?int
    {
        return $this->company?->id;
    }

    public function isPlatform(): bool
    {
        return $this->platform;
    }

    public function hasTenant(): bool
    {
        return $this->company !== null;
    }

    /** Runs a callback with the tenant scope lifted — for seeding and console work. */
    public function withoutScope(callable $callback): mixed
    {
        $company = $this->company;
        $platform = $this->platform;

        $this->asPlatform();

        try {
            return $callback();
        } finally {
            $this->company = $company;
            $this->platform = $platform;
        }
    }

    /** Runs a callback scoped to a specific tenant. */
    public function forCompany(Company $company, callable $callback): mixed
    {
        $previousCompany = $this->company;
        $previousPlatform = $this->platform;

        $this->set($company);

        try {
            return $callback();
        } finally {
            $this->company = $previousCompany;
            $this->platform = $previousPlatform;
        }
    }
}
