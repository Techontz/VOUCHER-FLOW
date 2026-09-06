<?php

namespace App\Services;

use App\Models\VoucherType;
use Illuminate\Support\Facades\DB;

/**
 * Per-tenant, per-type sequential numbering — e.g. PV-2026-001246.
 * The counter row is locked for update so two concurrent submissions cannot take
 * the same number.
 */
class VoucherNumberGenerator
{
    public function next(VoucherType $type): string
    {
        return DB::transaction(function () use ($type) {
            /** @var VoucherType $locked */
            $locked = VoucherType::whereKey($type->id)->lockForUpdate()->firstOrFail();

            $year = (int) now()->format('Y');

            if ($locked->reset_yearly && $locked->current_year !== $year) {
                $locked->current_year = $year;
                $locked->next_number = 1;
            }

            $sequence = (int) $locked->next_number;

            $locked->next_number = $sequence + 1;
            $locked->current_year = $locked->current_year ?: $year;
            $locked->save();

            return str_replace(
                ['{prefix}', '{year}', '{seq}'],
                [$locked->prefix, (string) $year, str_pad((string) $sequence, (int) $locked->seq_padding, '0', STR_PAD_LEFT)],
                $locked->number_format ?: '{prefix}-{year}-{seq}',
            );
        });
    }

    /** Shows the next number without consuming it — used by the create form. */
    public function preview(VoucherType $type): string
    {
        $year = (int) now()->format('Y');
        $sequence = ($type->reset_yearly && $type->current_year !== $year) ? 1 : (int) $type->next_number;

        return str_replace(
            ['{prefix}', '{year}', '{seq}'],
            [$type->prefix, (string) $year, str_pad((string) $sequence, (int) $type->seq_padding, '0', STR_PAD_LEFT)],
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
