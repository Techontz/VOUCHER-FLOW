{{--
  The printed voucher.

  Mirrors the on-screen A4 sheet, but built entirely from tables and absolute
  positioning: DomPDF has no flexbox and no grid, so the two-column body is a
  table and the authorisation band is a table of equal-width cells.

  The sheet stays white and ink-on-paper whatever appearance the application is
  wearing — this is a financial document, not a piece of the interface.
--}}
@php
    $ink = '#0b1220';
    $rule = '#d9dee8';
    $muted = '#6b7689';
    $wash = '#f4f7fb';
    $brand = $company?->primary_color ?: '#2E3192';

    $stampInk = [
        'signed' => '#1f3a8a',
        'approved' => '#0f7a54',
        'paid' => '#a3183a',
        'rejected' => '#a3183a',
    ];
@endphp
<!DOCTYPE html>
<html lang="{{ $locale }}">
<head>
    <meta charset="utf-8">
    <title>{{ $voucher->number }}</title>
    <style>
        @page { size: A4 portrait; margin: 12mm 12mm 10mm; }

        body {
            font-family: "DejaVu Sans", sans-serif;
            font-size: 8.5pt;
            color: {{ $ink }};
            margin: 0;
        }

        .brandrule { height: 3pt; background: {{ $brand }}; margin-bottom: 9pt; }

        table { border-collapse: collapse; width: 100%; }
        td, th { vertical-align: top; }

        .label {
            font-size: 5.8pt; letter-spacing: .11em; text-transform: uppercase;
            color: {{ $muted }}; font-weight: bold;
        }
        .value { font-size: 8.5pt; }
        .strong { font-weight: bold; }
        .muted { color: {{ $muted }}; }
        .num { font-size: 9pt; }

        .letterhead-name { font-size: 14pt; font-weight: bold; letter-spacing: -.2pt; }
        .doc-type { font-size: 11pt; font-weight: bold; letter-spacing: .06em; text-align: right; }
        .doc-number { font-size: 13pt; font-weight: bold; text-align: right; letter-spacing: -.2pt; }

        .chip {
            display: inline-block; border: 1pt solid {{ $brand }}; color: {{ $brand }};
            padding: 1.5pt 5pt; font-size: 6pt; font-weight: bold; letter-spacing: .1em;
        }

        .hr { border-top: 1.2pt solid {{ $ink }}; height: 1px; font-size: 0; line-height: 0; }
        .hr-light { border-top: .6pt solid {{ $rule }}; height: 1px; font-size: 0; line-height: 0; }

        .meta td { padding: 6pt 8pt 6pt 0; border-bottom: .6pt solid {{ $rule }}; }

        .particulars th {
            background: {{ $wash }}; border-top: .6pt solid {{ $rule }};
            border-bottom: .6pt solid {{ $rule }}; padding: 4pt 6pt; text-align: left;
        }
        .particulars td { padding: 6pt; border-bottom: .6pt solid {{ $rule }}; }
        .particulars .filler td { height: {{ $fillerHeight }}pt; }
        .particulars tfoot td {
            border-top: 1.6pt solid {{ $ink }}; background: {{ $wash }};
            padding: 6pt; font-weight: bold;
        }

        .panel { border: .6pt solid {{ $rule }}; }
        .panel-head {
            background: {{ $wash }}; border-bottom: .6pt solid {{ $rule }};
            padding: 4pt 6pt;
        }
        .panel td.k { padding: 3.5pt 6pt; width: 44%; border-bottom: .6pt solid {{ $rule }}; }
        .panel td.v { padding: 3.5pt 6pt; border-bottom: .6pt solid {{ $rule }}; }

        .words { border: .6pt solid {{ $rule }}; border-left: 2.4pt solid {{ $ink }}; background: {{ $wash }}; padding: 5pt 7pt; }

        .auth td {
            border: .6pt solid {{ $rule }}; padding: 6pt; width: 25%; height: 74pt;
        }

        .stamp {
            display: inline-block; border: 1.4pt solid currentColor; padding: 2pt 5pt;
            font-size: 7.5pt; font-weight: bold; letter-spacing: .12em;
        }
        .stamp-date { font-size: 5pt; letter-spacing: .04em; display: block; text-align: center; }

        .sigline { border-bottom: .6pt solid {{ $ink }}; height: 1px; font-size: 0; margin: 3pt 0 4pt; }

        .foot { font-size: 6.5pt; color: {{ $muted }}; }
    </style>
</head>
<body>

<div class="brandrule"></div>

{{-- ── Letterhead ─────────────────────────────────────────────────────── --}}
<table>
    <tr>
        @if ($logo)
            <td style="width: 92pt; padding-right: 10pt;">
                <img src="{{ $logo }}" style="max-width: 88pt; max-height: 40pt;" alt="">
            </td>
        @endif
        <td>
            <div class="letterhead-name">{{ $company?->legal_name ?: $company?->name }}</div>
            <div class="muted" style="font-size: 7pt; line-height: 1.5; margin-top: 2pt;">
                {{ $company?->address }}<br>
                {{ collect([$company?->phone, $company?->email])->filter()->implode(' · ') }}<br>
                {{ collect([$company?->website, $company?->tin ? 'TIN '.$company->tin : null])->filter()->implode(' · ') }}
            </div>
        </td>
        <td style="width: 150pt;">
            <div class="doc-type">{{ mb_strtoupper($typeLabel) }}</div>
            <div style="text-align: right; margin: 3pt 0;">
                <span class="chip">{{ $isBank ? 'BANK VOUCHER' : 'CASH VOUCHER' }}</span>
            </div>
            <div class="doc-number">{{ $voucher->number }}</div>
            <div class="muted" style="font-size: 6pt; text-align: right;">{{ $t['original'] }}</div>
        </td>
    </tr>
</table>

<div class="hr" style="margin: 8pt 0 0;"></div>

{{-- ── Meta strip ─────────────────────────────────────────────────────── --}}
<table class="meta">
    <tr>
        <td style="width: 25%;">
            <div class="label">{{ $t['date'] }}</div>
            <div class="value strong">{{ $voucher->voucher_date?->format('j M Y') }}</div>
        </td>
        <td style="width: 25%;">
            <div class="label">{{ $t['department'] }}</div>
            <div class="value strong">{{ $voucher->department?->name ?: '—' }}</div>
            <div class="muted" style="font-size: 6.5pt;">{{ $voucher->cost_centre }}</div>
        </td>
        <td style="width: 25%;">
            <div class="label">{{ $t['requestedBy'] }}</div>
            <div class="value strong">{{ $voucher->requester?->name }}</div>
            <div class="muted" style="font-size: 6.5pt;">{{ $voucher->requester?->job_title }}</div>
        </td>
        <td style="width: 25%;">
            <div class="label">{{ $t['category'] }}</div>
            <div class="value strong">{{ $voucher->category ?: '—' }}</div>
        </td>
    </tr>
</table>

{{-- ── Body: particulars on the left, payment on the right ────────────── --}}
<table style="margin-top: 9pt;">
    <tr>
        <td style="width: 60%; padding-right: 10pt;">
            <div class="label">{{ $t['payee'] }}</div>
            <div style="font-size: 12pt; font-weight: bold; margin-bottom: 7pt;">{{ $voucher->payee }}</div>

            <table class="particulars">
                <thead>
                    <tr>
                        <th class="label">Particulars</th>
                        <th class="label" style="text-align: right; width: 74pt;">Amount · {{ $voucher->currency }}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td>
                            <div class="strong" style="font-size: 9pt;">{{ $voucher->purpose }}</div>
                            @if ($voucher->description)
                                <div class="muted" style="margin-top: 3pt; line-height: 1.45;">{{ $voucher->description }}</div>
                            @endif
                            @if ($voucher->account_ref)
                                <div class="muted" style="margin-top: 3pt; font-size: 7pt;">{{ $t['reference'] }}: {{ $voucher->account_ref }}</div>
                            @endif
                        </td>
                        <td style="text-align: right;" class="strong num">
                            {{ number_format((float) $voucher->amount) }}
                        </td>
                    </tr>
                    {{-- The form's remaining rules: a voucher book leaves room. --}}
                    <tr class="filler"><td></td><td></td></tr>
                </tbody>
                <tfoot>
                    <tr>
                        <td class="label" style="font-size: 6.5pt;">{{ $t['totalPayable'] }}</td>
                        <td style="text-align: right; font-size: 12pt;">{{ number_format((float) $voucher->amount) }}</td>
                    </tr>
                </tfoot>
            </table>

            <div class="words" style="margin-top: 6pt;">
                <div class="label" style="font-size: 5.4pt;">{{ $t['amountWords'] }}</div>
                <div style="font-style: italic; font-size: 8pt;">{{ $voucher->amount_in_words ?: $amountText }}</div>
            </div>
        </td>

        <td style="width: 40%;">
            <div class="panel">
                <div class="panel-head label">Payment particulars</div>
                <table>
                    @foreach ($particulars as [$key, $val])
                        <tr>
                            <td class="k label" style="font-size: 5.4pt;">{{ $key }}</td>
                            <td class="v {{ $loop->first ? 'strong' : '' }}" style="font-size: {{ $loop->first ? '9.5pt' : '8pt' }};">{{ $val }}</td>
                        </tr>
                    @endforeach
                </table>
            </div>

            @if ($isBank && $company?->bank_name)
                <div class="panel" style="margin-top: 7pt; background: {{ $wash }};">
                    <div style="padding: 5pt 6pt;">
                        <div class="label" style="font-size: 5.4pt;">Drawn on</div>
                        <div class="strong" style="margin-top: 1pt;">{{ $company->bank_name }}</div>
                        <div class="muted" style="font-size: 7.5pt;">{{ $company->bank_account_name }}</div>
                        <div class="muted" style="font-size: 7.5pt;">
                            {{ collect([$company->bank_account_number, $company->bank_branch])->filter()->implode(' · ') }}
                        </div>
                    </div>
                </div>
            @endif

            <div class="panel" style="margin-top: 7pt;">
                <div style="padding: 5pt 6pt;">
                    <div class="label" style="font-size: 5.4pt;">{{ $t['attachments'] }}</div>
                    @forelse ($voucher->attachments as $file)
                        <div style="font-size: 7.5pt; margin-top: 2pt;">• {{ $file->original_name ?? $file->name }}</div>
                    @empty
                        <div class="muted" style="font-size: 7.5pt; margin-top: 2pt;">None attached</div>
                    @endforelse
                </div>
            </div>

            @if ($voucher->notes_to_approver)
                <div class="panel" style="margin-top: 7pt;">
                    <div style="padding: 5pt 6pt;">
                        <div class="label" style="font-size: 5.4pt;">Remarks</div>
                        <div class="muted" style="font-size: 7.5pt; line-height: 1.45; margin-top: 2pt;">{{ $voucher->notes_to_approver }}</div>
                    </div>
                </div>
            @endif
        </td>
    </tr>
</table>

{{-- ── Authorisation ──────────────────────────────────────────────────── --}}
<div class="label" style="margin: 11pt 0 4pt;">{{ $t['authorisation'] }}</div>

<table class="auth">
    <tr>
        @foreach ($signatories as $block)
            <td>
                <div class="label" style="font-size: 5.4pt;">{{ $block['label'] }}</div>

                <div style="height: 34pt; text-align: center; padding-top: 3pt;">
                    @if ($block['signature'])
                        <img src="{{ $block['signature'] }}" style="max-height: 24pt; max-width: 72pt;" alt="">
                    @endif
                    @if ($block['stamp'] ?? null)
                        <div style="color: {{ $stampInk[$block['stamp']] ?? $ink }}; margin-top: 1pt;">
                            <span class="stamp">{{ mb_strtoupper($block['stamp']) }}</span>
                        </div>
                    @endif
                </div>

                <div class="sigline"></div>
                <div class="strong" style="font-size: 7.5pt;">{{ $block['name'] ?: '—' }}</div>
                <div class="muted" style="font-size: 6.2pt; line-height: 1.35;">{{ $block['meta'] }}</div>
            </td>
        @endforeach
    </tr>
</table>

{{-- ── Footer ─────────────────────────────────────────────────────────── --}}
<div class="hr-light" style="margin-top: 11pt;"></div>
<table style="margin-top: 5pt;">
    <tr>
        <td class="foot" style="line-height: 1.5;">
            {{ $company?->voucher_footer_text }}<br>
            {{ $t['verificationCode'] }}: <span class="strong">{{ $voucher->verification_code }}</span>
        </td>
        <td class="foot" style="text-align: right; line-height: 1.5;">
            {{ $statusLabel }}<br>
            {{ $t['generated'] }} {{ $generatedAt }}
        </td>
    </tr>
</table>

</body>
</html>
