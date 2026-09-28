<?php

namespace App\Support;

/**
 * The catalogue of voucher designs.
 *
 * A template is presentation only: every one renders the same document data
 * (see App\Services\VoucherDocument) through the shared parts in
 * resources/views/vouchers/parts, arranged and styled its own way. Adding a
 * design is two steps — a Blade view at resources/views/vouchers/templates/{key}
 * and an entry here — and nothing about vouchers, workflows or storage changes.
 */
final class VoucherTemplates
{
    public const DEFAULT = 'classic';

    /** @var array<string, array{name: array{en: string, sw: string}, description: array{en: string, sw: string}}> */
    private const CATALOGUE = [
        'classic' => [
            'name' => ['en' => 'Classic Corporate', 'sw' => 'Kampuni ya Kawaida'],
            'description' => [
                'en' => 'Company header, a metadata strip, a large ruled particulars table with payment details beside it, and a full signature band.',
                'sw' => 'Kichwa cha kampuni, mstari wa taarifa, jedwali kubwa la maelezo na malipo pembeni, na sahihi kamili chini.',
            ],
        ],
        'modern' => [
            'name' => ['en' => 'Modern Corporate', 'sw' => 'Kampuni ya Kisasa'],
            'description' => [
                'en' => 'A contemporary header, the amount as the headline, clear information blocks and a card-style approval area.',
                'sw' => 'Kichwa cha kisasa, kiasi kama kichwa kikuu, sehemu za taarifa zilizo wazi na idhini za mtindo wa kadi.',
            ],
        ],
        'finance' => [
            'name' => ['en' => 'Finance Professional', 'sw' => 'Mtaalamu wa Fedha'],
            'description' => [
                'en' => 'Opens with the financial summary: amount, method, bank and references first, then an accounting-style ledger and sign-off table.',
                'sw' => 'Huanza na muhtasari wa fedha: kiasi, njia, benki na kumbukumbu, kisha daftari la hesabu na jedwali la uidhinishaji.',
            ],
        ],
        'executive' => [
            'name' => ['en' => 'Executive', 'sw' => 'Mtendaji'],
            'description' => [
                'en' => 'Elegant serif typography, a centred company identity, generous whitespace and a prominent signature line.',
                'sw' => 'Herufi za serif za kifahari, utambulisho wa kampuni katikati, nafasi pana na mistari ya sahihi inayoonekana.',
            ],
        ],
        'structured' => [
            'name' => ['en' => 'Structured Two-Column', 'sw' => 'Safu Mbili Zilizopangwa'],
            'description' => [
                'en' => 'Request details on the left, the money on the right — amount, method, bank, account and reference — with a strong approval band below.',
                'sw' => 'Taarifa za ombi kushoto, fedha kulia — kiasi, njia, benki, akaunti na kumbukumbu — na idhini imara chini.',
            ],
        ],
        'detailed' => [
            'name' => ['en' => 'Detailed Business', 'sw' => 'Biashara Kamili'],
            'description' => [
                'en' => 'Clearly separated numbered sections for request, expense, payment, supporting documents and authorisation.',
                'sw' => 'Sehemu zenye namba zilizotenganishwa: ombi, gharama, malipo, nyaraka na uidhinishaji.',
            ],
        ],
        'minimal' => [
            'name' => ['en' => 'Minimal Professional', 'sw' => 'Rahisi ya Kitaalamu'],
            'description' => [
                'en' => 'Thin rules, large readable type and generous whitespace, with a quiet but complete hierarchy.',
                'sw' => 'Mistari myembamba, herufi kubwa zinazosomeka na nafasi pana, kwa mpangilio kamili na tulivu.',
            ],
        ],
        'formal' => [
            'name' => ['en' => 'Formal Document', 'sw' => 'Hati Rasmi'],
            'description' => [
                'en' => 'A bordered official form: boxed title, strong voucher metadata, gridded fields and a formal signature section.',
                'sw' => 'Fomu rasmi yenye mipaka: kichwa ndani ya kisanduku, taarifa za vocha, sehemu za gridi na sahihi rasmi.',
            ],
        ],
        'split' => [
            'name' => ['en' => 'Modern Split', 'sw' => 'Mgawanyo wa Kisasa'],
            'description' => [
                'en' => 'A coloured side panel carries the company and voucher details; the main column holds particulars, amount, payment and approvals.',
                'sw' => 'Paneli ya rangi pembeni ina kampuni na taarifa za vocha; safu kuu ina maelezo, kiasi, malipo na idhini.',
            ],
        ],
        'enterprise' => [
            'name' => ['en' => 'Enterprise', 'sw' => 'Shirika'],
            'description' => [
                'en' => 'A banded header, reference strip, structured finance block, a full approval workflow and a detailed footer.',
                'sw' => 'Kichwa chenye utepe, mstari wa kumbukumbu, sehemu ya fedha, mfuatano kamili wa idhini na sehemu ya chini ya kina.',
            ],
        ],
    ];

    /** @return list<string> */
    public static function keys(): array
    {
        return array_keys(self::CATALOGUE);
    }

    public static function exists(?string $key): bool
    {
        return $key !== null && isset(self::CATALOGUE[$key]);
    }

    /** A usable key: unknown or retired designs fall back to the default. */
    public static function resolve(?string $key): string
    {
        return self::exists($key) ? $key : self::DEFAULT;
    }

    public static function name(?string $key, string $locale = 'en'): string
    {
        $entry = self::CATALOGUE[self::resolve($key)];

        return $entry['name'][$locale] ?? $entry['name']['en'];
    }

    public static function view(string $key): string
    {
        return 'vouchers.templates.'.self::resolve($key);
    }

    /** @return list<array{key: string, number: int, name: string, name_sw: string, description: string, description_sw: string, is_default: bool}> */
    public static function all(): array
    {
        $out = [];
        $i = 0;

        foreach (self::CATALOGUE as $key => $entry) {
            $out[] = [
                'key' => $key,
                'number' => ++$i,
                'name' => $entry['name']['en'],
                'name_sw' => $entry['name']['sw'],
                'description' => $entry['description']['en'],
                'description_sw' => $entry['description']['sw'],
                'is_default' => $key === self::DEFAULT,
            ];
        }

        return $out;
    }

    /** How many times a company may change its own design after registration. */
    public static function selfServiceChanges(): int
    {
        return max(0, (int) config('vouchflow.voucher_template_self_changes', 1));
    }
}
