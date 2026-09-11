<?php

namespace App\Policies;

use App\Models\Company;
use App\Models\User;

/**
 * A tenant's own settings, branding and people are the company administrator's
 * to change. Everyone else in the tenant may read the company they belong to —
 * the letterhead has to render on their vouchers — and nobody may touch another
 * company at all, which the tenant scope has already made true.
 */
class CompanyPolicy
{
    public function view(User $user, Company $company): bool
    {
        return $user->isSuperAdmin() || $user->company_id === $company->id;
    }

    public function update(User $user, Company $company): bool
    {
        return $user->isSuperAdmin()
            || ($user->isCompanyAdmin() && $user->company_id === $company->id);
    }

    /** Logo, colours, letterhead and banking details. */
    public function brand(User $user, Company $company): bool
    {
        return $this->update($user, $company);
    }

    /** Plans, invoices and payment methods. */
    public function manageBilling(User $user, Company $company): bool
    {
        return $this->update($user, $company);
    }
}
