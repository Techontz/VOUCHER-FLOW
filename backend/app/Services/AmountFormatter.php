<?php

namespace App\Services;

/**
 * Renders an amount as the words printed on the voucher body.
 */
class AmountFormatter
{
    private const UNITS = [
        '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
        'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen',
        'Eighteen', 'Nineteen',
    ];

    private const TENS = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

    private const CURRENCY_WORDS = [
        'TZS' => ['shillings', 'cents'],
        'KES' => ['shillings', 'cents'],
        'USD' => ['dollars', 'cents'],
        'EUR' => ['euros', 'cents'],
        'GBP' => ['pounds', 'pence'],
    ];

    public function money(float $amount, string $currency = 'TZS'): string
    {
        return $currency.' '.number_format($amount, $this->decimals($amount));
    }

    public function decimals(float $amount): int
    {
        return fmod($amount, 1.0) === 0.0 ? 0 : 2;
    }

    public function inWords(float $amount, string $currency = 'TZS'): string
    {
        [$major, $minor] = self::CURRENCY_WORDS[strtoupper($currency)] ?? ['units', 'cents'];

        $whole = (int) floor(abs($amount));
        $fraction = (int) round((abs($amount) - $whole) * 100);

        if ($whole === 0 && $fraction === 0) {
            return 'Zero '.$major.' only';
        }

        $words = $whole === 0 ? 'Zero' : $this->convert($whole);
        $text = $words.' '.$major;

        if ($fraction > 0) {
            $text .= ' and '.$this->convert($fraction).' '.$minor;
        }

        return $text.' only';
    }

    private function convert(int $number): string
    {
        $parts = [];

        $scales = [
            1_000_000_000 => 'billion',
            1_000_000 => 'million',
            1_000 => 'thousand',
        ];

        foreach ($scales as $value => $label) {
            if ($number >= $value) {
                $parts[] = $this->underThousand(intdiv($number, $value)).' '.$label;
                $number %= $value;
            }
        }

        if ($number > 0) {
            $parts[] = $this->underThousand($number);
        }

        return implode(' ', $parts);
    }

    private function underThousand(int $number): string
    {
        if ($number < 20) {
            return self::UNITS[$number];
        }

        if ($number < 100) {
            $remainder = $number % 10;

            return self::TENS[intdiv($number, 10)].($remainder ? '-'.self::UNITS[$remainder] : '');
        }

        $remainder = $number % 100;

        return self::UNITS[intdiv($number, 100)].' hundred'.($remainder ? ' '.$this->underThousand($remainder) : '');
    }
}
