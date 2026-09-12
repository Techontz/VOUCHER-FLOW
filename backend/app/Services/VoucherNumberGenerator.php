<?php

namespace App\Services;

use App\Models\Voucher;
use App\Models\VoucherType;
use Illuminate\Support\Facades\DB;

/**
 * Per-tenant, per-type sequential numbering — e.g. PV-2026-001246.
 *
 * The counter on voucher_types is an optimisation, not the source of truth.
 * The vouchers table is, because it carries the unique key the database will
 * actually enforce, so every number issued here is reconciled against the
 * numbers already on disk before it is handed out. A counter that has drifted
 * behind reality — reset, restored from a backup, or seeded alongside rows it
 * did not issue — corrects itself on the next call instead of colliding.
 *
 * The type's row is locked for the whole transaction, so two concurrent
 * submissions serialise here rather than racing to the same number.
 */
class VoucherNumberGenerator
{
    public function next(VoucherType $type): string
    {
        return DB::transaction(function () use ($type) {
            // Locked by primary key, without the tenant scope: the caller has
            // already resolved this type through a scoped, authorised query, so
            // re-applying the scope here adds no protection and one failure
            // mode — it fails closed wherever no tenant happens to be resolved,
            // such as a console command or a test. Tenancy is still enforced on
            // the reconciliation query below, by explicit company_id.
            /** @var VoucherType $locked */
            $locked = VoucherType::withoutGlobalScopes()
                ->whereKey($type->id)
                ->lockForUpdate()
                ->firstOrFail();

            $year = (int) now()->format('Y');

            // Numeric comparison, deliberately. These columns carry no cast on
            // some paths and MySQL hands integers back as strings under
            // emulated prepared statements, where `!==` is true for every value
            // and reset the sequence to 1 on EVERY call — which is how a live
            // tenant with forty-one vouchers came to be told its next number
            // was 000001.
            if ($locked->reset_yearly && (int) $locked->current_year !== $year) {
                $locked->current_year = $year;
                $locked->next_number = 1;
            }

            // Whichever is further along: the counter, or reality.
            $sequence = max((int) $locked->next_number, $this->highestIssued($locked, $year) + 1);

            $locked->next_number = $sequence + 1;
            $locked->current_year = (int) $locked->current_year ?: $year;
            $locked->save();

            return $this->render($locked, $year, $sequence);
        });
    }

    /** Shows the next number without consuming it — used by the create form. */
    public function preview(VoucherType $type): string
    {
        $year = (int) now()->format('Y');

        $counter = ($type->reset_yearly && (int) $type->current_year !== $year)
            ? 1
            : (int) $type->next_number;

        // Same reconciliation as next(), or the form would promise a number
        // that the insert then refuses.
        $sequence = max($counter, $this->highestIssued($type, $year) + 1);

        return $this->render($type, $year, $sequence);
    }

    /**
     * The largest sequence already issued for this company, type and year.
     *
     * Matched on the rendered stem — "PV-2026-" — so a tenant that changed its
     * number_format or prefix starts a fresh series rather than inheriting the
     * old one's high-water mark. Ordered by length first because zero padding
     * only sorts correctly while every number is the same width; once a series
     * outgrows its padding, plain string ordering puts 999999 above 1000000.
     */
    private function highestIssued(VoucherType $type, int $year): int
    {
        $stem = $this->render($type, $year, null);

        if ($stem === '') {
            return 0;
        }

        $highest = Voucher::withoutGlobalScopes()
            ->where('company_id', $type->company_id)
            ->where('voucher_type_id', $type->id)
            ->where('number', 'like', $stem.'%')
            ->orderByRaw('LENGTH(number) DESC, number DESC')
            ->value('number');

        if (! $highest) {
            return 0;
        }

        $tail = substr($highest, strlen($stem));

        return ctype_digit($tail) ? (int) $tail : 0;
    }

    /**
     * Renders a number in the type's own format.
     *
     * A null sequence yields the stem that every number in the series shares,
     * which is what highestIssued() matches on — one formatter, so the search
     * pattern and the issued number can never disagree.
     */
    private function render(VoucherType $type, int $year, ?int $sequence): string
    {
        $padded = $sequence === null
            ? ''
            : str_pad((string) $sequence, (int) $type->seq_padding, '0', STR_PAD_LEFT);

        return str_replace(
            ['{prefix}', '{year}', '{seq}'],
            [$type->prefix, (string) $year, $padded],
            $type->number_format ?: '{prefix}-{year}-{seq}',
        );
    }

    /** Short, human-quotable code printed on the completed voucher. */
    public function verificationCode(): string
    {
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        $pick = fn (int $n) => collect(range(1, $n))
            ->map(fn () => $alphabet[random_int(0, strlen($alphabet) - 1)])
            ->implode('');

        return 'VF-'.$pick(4).'-'.$pick(4);
    }
}
