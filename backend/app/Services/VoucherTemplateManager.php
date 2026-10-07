<?php

namespace App\Services;

use App\Models\Company;
use App\Models\User;
use App\Models\Voucher;
use App\Models\VoucherTemplateChange;
use App\Support\VoucherTemplates;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * Every change of a company's voucher design goes through here.
 *
 * The rules, all enforced server-side:
 * - at registration (or when the platform creates the company) the design is
 *   chosen freely and nothing is spent;
 * - afterwards the company administrator may change it themselves a limited
 *   number of times (config vouchflow.voucher_template_self_changes, 1);
 * - the platform's super admin may change it at any time, without spending
 *   the company's allowance.
 *
 * Changing the design must never rewrite a document already issued, so
 * before the company's design moves, every finalised voucher that was still
 * following it is pinned to the old design.
 */
class VoucherTemplateManager
{
    /** Statuses whose document is issued: it must look the same forever after. */
    public const FINALISED = [
        Voucher::STATUS_APPROVED,
        Voucher::STATUS_PAID,
        Voucher::STATUS_REJECTED,
        Voucher::STATUS_CANCELLED,
    ];

    public function __construct(private readonly AuditLogger $audit) {}

    /** The design chosen when the company is created. Spends nothing. */
    public function initial(Company $company, ?string $template, ?User $actor, string $source): void
    {
        $template = VoucherTemplates::resolve($template);

        $company->forceFill(['voucher_template' => $template])->save();

        $this->record($company, null, $template, $actor, $source, null, false);
    }

    /** A company administrator changing their own design: limited. */
    public function changeByCompany(Company $company, string $template, User $actor, ?string $reason = null): Company
    {
        $this->assertKnown($template);

        return DB::transaction(function () use ($company, $template, $actor, $reason) {
            // Locked so two simultaneous requests cannot both spend the last change.
            $locked = Company::whereKey($company->id)->lockForUpdate()->firstOrFail();

            if ($locked->voucherTemplateChangesRemaining() <= 0) {
                throw new HttpException(403, 'Your voucher template can no longer be changed from company settings. Contact VouchFlow support (support@vouchflow.co.tz) or your platform administrator if you need another change.');
            }

            $this->assertDifferent($locked, $template);

            $previous = VoucherTemplates::resolve($locked->voucher_template);
            $this->pinIssuedDocuments($locked, $previous);

            $locked->forceFill([
                'voucher_template' => $template,
                'voucher_template_changes_used' => (int) $locked->voucher_template_changes_used + 1,
            ])->save();

            $this->record($locked, $previous, $template, $actor, VoucherTemplateChange::SOURCE_COMPANY_ADMIN, $reason, true);

            return $locked;
        });
    }

    /** The platform's override: any time, spends nothing of the company's. */
    public function changeByPlatform(Company $company, string $template, User $actor, ?string $reason = null): Company
    {
        $this->assertKnown($template);

        return DB::transaction(function () use ($company, $template, $actor, $reason) {
            $locked = Company::whereKey($company->id)->lockForUpdate()->firstOrFail();
            $this->assertDifferent($locked, $template);

            $previous = VoucherTemplates::resolve($locked->voucher_template);
            $this->pinIssuedDocuments($locked, $previous);

            $locked->forceFill(['voucher_template' => $template])->save();

            $this->record($locked, $previous, $template, $actor, VoucherTemplateChange::SOURCE_SUPER_ADMIN, $reason, false);

            return $locked;
        });
    }

    /** @return list<array<string, mixed>> */
    public function history(Company $company): array
    {
        return VoucherTemplateChange::where('company_id', $company->id)
            ->orderByDesc('id')
            ->get()
            ->map->toApi()
            ->all();
    }

    /**
     * Issued documents that were still following the company's design keep
     * the one they were issued in. Vouchers still moving follow the new one.
     */
    private function pinIssuedDocuments(Company $company, string $previous): void
    {
        Voucher::acrossTenants()
            ->where('company_id', $company->id)
            ->whereNull('voucher_template')
            ->whereIn('status', self::FINALISED)
            ->toBase()
            ->update(['voucher_template' => $previous]);
    }

    private function record(Company $company, ?string $previous, string $new, ?User $actor, string $source, ?string $reason, bool $counted): void
    {
        VoucherTemplateChange::create([
            'company_id' => $company->id,
            'previous_template' => $previous,
            'new_template' => $new,
            'changed_by' => $actor?->id,
            'changed_by_name' => $actor?->name,
            'changed_by_role' => $actor?->role,
            'source' => $source,
            'reason' => $reason,
            'counted' => $counted,
        ]);

        $description = $previous
            ? 'Voucher template changed from '.VoucherTemplates::name($previous).' to '.VoucherTemplates::name($new)." for {$company->name}"
            : 'Voucher template set to '.VoucherTemplates::name($new)." for {$company->name}";

        $this->audit->log(
            'company.voucher_template_changed',
            $description.($reason ? " — {$reason}" : ''),
            $company,
            $previous ? ['voucher_template' => $previous] : null,
            ['voucher_template' => $new, 'source' => $source],
            $company->id,
            $actor,
        );
    }

    private function assertKnown(string $template): void
    {
        if (! VoucherTemplates::exists($template)) {
            throw ValidationException::withMessages(['template' => ['That voucher template does not exist.']]);
        }
    }

    private function assertDifferent(Company $company, string $template): void
    {
        if (VoucherTemplates::resolve($company->voucher_template) === $template) {
            throw ValidationException::withMessages(['template' => ['Your vouchers already use this template.']]);
        }
    }
}
