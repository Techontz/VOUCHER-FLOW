{{--
  02 · Modern Corporate.

  Contemporary and card-based; the amount is the headline. Section order:
    1. header — logo + company left; document title as a brand pill and the
       bank/cash kind right
    2. HERO row — voucher number (large), date and status on the left; the
       total set very large in a brand-tinted rounded block with the amount
       in words on the right
    3. requester information — four rounded cards: requested by · department
       (+ cost centre) · category · date / reference
    4. particulars — a clean table (payee | particulars | reference | amount)
       with hairlines only and a total line
    5. payment details as cards — payment method · payee bank account (bank,
       account name, number, branch — or cash float / received by) ·
       reference & settlement; then drawn on · supporting documents · remarks
    6. approvals — cards in a row with a brand top edge; pending ones dashed
       and deliberately empty
    7. footer strip — tinted, footer text + verification on the left, QR right
--}}
@extends('vouchers.layout')

@php
    $b = $doc['brand']; $t = $doc['t']; $v = $doc['voucher']; $c = $doc['company']; $p = $doc['payment'];
    $line = '#e2e6ee'; $body = '#26324a';
    $isCash = $v['kind'] === 'cash';
    $dash = fn ($x) => filled($x) ? $x : '—';
    $sigs = $doc['signatories'];
    $perRow = min(4, max(2, count($sigs)));
    $sigRows = array_chunk($sigs, $perRow);
    $apW = round((100 - 2 * ($perRow - 1)) / $perRow, 2);

    // Settlement lines: always the reference, then whatever the payment has recorded.
    $settle = array_values(array_filter([
        [$t['chequeNo'], $p['cheque_no']],
        [$t['paidOn'], $p['paid_on']],
        [$t['paymentRef'], $p['payment_ref']],
        [$t['amountPaid'], $p['amount_paid']],
        [$t['balance'], $p['balance']],
    ], fn ($r) => filled($r[1])));

    $account = $isCash
        ? [[$t['cashFloat'], $p['cash_float']], [$t['receivedBy'], $p['received_by']]]
        : [[$t['payeeBank'], $p['bank']], [$t['accountName'], $p['account_name']], [$t['accountNo'], $p['account_no']], [$t['branch'], $p['branch']]];

    $drawn = ! $isCash && $c['bank'];
@endphp

@section('page_margin', '7mm 12mm 6mm')

@section('styles')
    body { line-height: 1.3; }
    .m-name { font-size: 15pt; font-weight: bold; letter-spacing: -.2pt; color: #0b1220; line-height: 1.2; }
    .m-lines { font-size: 8.5pt; color: #4a5568; margin-top: 2pt; }
    .m-pill { display: inline-block; background: {{ $b['primary'] }}; color: {{ $b['on_primary'] }}; padding: 4pt 12pt; border-radius: 11pt; font-size: 10pt; font-weight: bold; letter-spacing: .1em; text-transform: uppercase; }
    .m-kind { display: inline-block; border: .8pt solid {{ $b['tint_strong'] }}; background: #fff; color: {{ $b['ink'] }}; padding: 2pt 9pt; border-radius: 9pt; font-size: 8pt; font-weight: bold; letter-spacing: .1em; text-transform: uppercase; }

    .m-hero { background: {{ $b['tint'] }}; border: .8pt solid {{ $b['tint_strong'] }}; border-radius: 10pt; padding: 8pt 14pt 9pt; }
    .m-amount { font-size: 28pt; font-weight: bold; letter-spacing: -.8pt; line-height: 1.1; color: {{ $b['ink'] }}; }
    .m-cur { font-size: 13pt; font-weight: bold; color: {{ $b['ink'] }}; }
    .m-number { font-size: 19pt; font-weight: bold; letter-spacing: -.4pt; line-height: 1.15; color: #0b1220; white-space: nowrap; }
    .m-status { display: inline-block; background: {{ $b['secondary_tint'] }}; color: #0b1220; border-radius: 8pt; padding: 2pt 9pt; font-size: 9pt; font-weight: bold; }
    .m-dot { display: inline-block; width: 6pt; height: 6pt; border-radius: 3pt; background: {{ $b['primary'] }}; }

    .m-card { border: .8pt solid {{ $line }}; border-radius: 7pt; padding: 5pt 9pt; background: #fff; }
    .m-val { font-size: 10.5pt; font-weight: bold; color: #0b1220; margin-top: 1pt; }
    .m-kv td { padding: 1.5pt 0; font-size: 9.5pt; color: #0b1220; }
    .m-kv td.k { color: #5b6678; font-size: 8.5pt; width: 46%; padding-right: 4pt; white-space: nowrap; }

    .m-tbl th { padding: 4pt 8pt; border-bottom: .8pt solid {{ $b['tint_strong'] }}; }
    .m-tbl td { padding: 5pt 8pt; border-bottom: .6pt solid {{ $line }}; }
    .m-tbl .tot td { border-bottom: 0; padding-top: 5pt; padding-bottom: 0; }

    .m-appr { border: .8pt solid {{ $line }}; border-top: 3.5pt solid {{ $b['primary'] }}; border-radius: 7pt; padding: 6pt 7pt 6pt; background: #fff; }
    .m-appr-pending { border: .9pt dashed #b3bccb; border-top: 3.5pt dashed #c8cfdb; background: #fbfcfd; }
    .m-appr-rejected { border-top-color: #a3183a; }
    .m-sigline { border-bottom: .8pt solid #0b1220; height: 1px; font-size: 0; line-height: 0; margin: 1pt 0 4pt; }
    .m-sigline-pending { border-bottom: .8pt dashed #8a94a6; }
    .m-foot { background: {{ $b['tint'] }}; border-radius: 8pt; padding: 4pt 6pt 4pt 12pt; }
    .m-auth { page-break-inside: avoid; }
    .m-auth tr { page-break-inside: avoid; }
@endsection

@section('content')
{{-- 1 · header --}}
<table>
    <tr>
        <td style="width: {{ $c['logo'] ? 118 : 56 }}pt; vertical-align: middle; padding-right: 10pt;">@include('vouchers.parts.logo', ['height' => 46, 'width' => 108])</td>
        <td style="vertical-align: middle;">
            <div class="m-name">{{ $c['name'] }}</div>
            <div class="m-lines">@include('vouchers.parts.company-lines')</div>
            @if ($c['header_text'])<div style="font-size: 8.5pt; margin-top: 1pt; color: {{ $body }};">{{ $c['header_text'] }}</div>@endif
        </td>
        <td style="width: 190pt; vertical-align: middle; text-align: right;">
            <span class="m-pill">{{ $v['type_label'] }}</span>
            <div style="margin-top: 5pt;"><span class="m-kind">{{ $v['kind_label'] }}</span></div>
        </td>
    </tr>
</table>

{{-- 2 · hero --}}
<table style="margin-top: 8pt;">
    <tr>
        <td style="width: 40%; vertical-align: middle; padding-right: 12pt;">
            <div class="t-label">{{ $t['voucherNo'] }}</div>
            <div class="m-number">{{ $v['number'] }}</div>
            <table style="margin-top: 6pt; width: auto;">
                <tr>
                    <td style="padding-right: 14pt;"><div class="t-label">{{ $t['date'] }}</div><div class="m-val">{{ $v['date'] }}</div></td>
                    <td><div class="t-label">{{ $t['status'] }}</div><div style="margin-top: 1pt;"><span class="m-status"><span class="m-dot"></span>&nbsp; {{ $v['status_label'] }}</span></div></td>
                </tr>
            </table>
        </td>
        <td style="width: 60%;">
            <div class="m-hero">
                <div class="t-label" style="color: {{ $b['ink'] }};">{{ $t['totalPayable'] }}</div>
                <div style="margin-top: 2pt;"><span class="m-cur">{{ $v['currency'] }}</span>&nbsp;<span class="m-amount">{{ $v['amount'] }}</span></div>
                <div style="margin-top: 3pt; border-top: .8pt solid {{ $b['tint_strong'] }}; padding-top: 4pt; font-size: 10pt; color: #0b1220;">
                    <span class="t-label" style="color: {{ $b['ink'] }};">{{ $t['amountWords'] }}</span>&nbsp;
                    <span class="i">{{ $v['amount_words'] }}</span>
                </div>
            </div>
        </td>
    </tr>
</table>

{{-- 3 · requester information --}}
@php
    $info = [
        [$t['requestedBy'], $v['requester'], $v['requester_title']],
        [$t['department'], $v['department'], $v['cost_centre'] ? $t['costCentre'].' '.$v['cost_centre'] : null],
        [$t['category'], $v['category'], null],
        [$t['reference'], $dash($v['reference']), $v['submitted'] ? $t['date'].' '.$v['submitted'] : null],
    ];
@endphp
<table style="margin-top: 8pt;">
    <tr>
        @foreach ($info as [$label, $value, $sub])
            <td style="width: 25%; padding: 0 {{ $loop->last ? 0 : 4 }}pt 0 {{ $loop->first ? 0 : 4 }}pt;">
                <div class="m-card" style="background: {{ $loop->first ? $b['secondary_tint'] : '#fff' }};">
                    <div class="t-label">{{ $label }}</div>
                    <div class="m-val">{{ $value }}</div>
                    <div class="t-meta">{{ $sub ?: ' ' }}&nbsp;</div>
                </div>
            </td>
        @endforeach
    </tr>
</table>

{{-- 4 · particulars --}}
<table class="m-tbl" style="margin-top: 7pt;">
    <tr>
        <th class="t-label" style="width: 25%; padding-left: 0;">{{ $t['payee'] }}</th>
        <th class="t-label">{{ $t['particulars'] }}</th>
        <th class="t-label r" style="width: 92pt; padding-right: 0;">{{ $t['amount'] }} · {{ $v['currency'] }}</th>
    </tr>
    <tr>
        <td style="padding-left: 0;"><div class="b" style="font-size: 11pt; color: #0b1220;">{{ $v['payee'] }}</div></td>
        <td>
            <div class="b" style="font-size: 10.5pt; color: #0b1220;">{{ $dash($v['purpose']) }}</div>
            @if ($v['description'])<div style="margin-top: 2pt; color: {{ $body }};">{{ $v['description'] }}</div>@endif
            @if ($v['reference'])<div class="t-meta" style="margin-top: 3pt;">{{ $t['reference'] }}: <span class="b" style="color: #0b1220;">{{ $v['reference'] }}</span></div>@endif
        </td>
        <td class="r b nowrap" style="font-size: 11pt; color: #0b1220; padding-right: 0;">{{ $v['amount'] }}</td>
    </tr>
</table>

{{-- 5 · payment details --}}
<div class="t-label" style="margin-top: 7pt; color: #0b1220;">{{ $t['paymentDetails'] }}</div>
<table style="margin-top: 4pt; border-collapse: separate; border-spacing: 0;">
    <tr>
        <td class="m-card" style="width: 25%;">
            <div class="t-label">{{ $t['paymentMethod'] }}</div>
            <div class="m-val" style="font-size: 12pt;">{{ $dash($p['method']) }}</div>
            <div class="t-label" style="margin-top: 4pt;">{{ $t['voucherType'] }}</div>
            <div style="font-size: 9.5pt; color: #0b1220;">{{ $dash($p['type']) }}</div>
            <div class="t-meta" style="margin-top: 2pt;">{{ $t['currency'] }}: <span class="b" style="color: #0b1220;">{{ $dash($p['currency']) }}</span></div>
        </td>
        <td style="width: 1.5%;"></td>
        <td class="m-card" style="width: 42%; border-left: 3pt solid {{ $b['primary'] }};">
            <div class="t-label">{{ $isCash ? $t['cash'] : $t['payeeBank'] }}</div>
            <table class="m-kv" style="margin-top: 2pt;">
                @foreach ($account as [$k, $val])
                    <tr><td class="k" style="width: 30%;">{{ $k }}</td><td class="{{ $loop->first ? 'b' : '' }}">{{ $dash($val) }}</td></tr>
                @endforeach
            </table>
        </td>
        <td style="width: 1.5%;"></td>
        <td class="m-card" style="width: 30%;">
            <div class="t-label">{{ $t['reference'] }}</div>
            <div class="m-val">{{ $dash($p['reference']) }}</div>
            <table class="m-kv" style="margin-top: 3pt;">
                @forelse ($settle as [$k, $val])
                    <tr><td class="k" style="width: 40%;">{{ $k }}</td><td class="nowrap">{{ $val }}</td></tr>
                @empty
                    <tr><td class="k">{{ $t['paymentRef'] }}</td><td>—</td></tr>
                @endforelse
            </table>
        </td>
    </tr>
</table>
<table style="margin-top: 6pt; border-collapse: separate; border-spacing: 0;">
    <tr>
        @if ($drawn)
            <td class="m-card" style="width: 33%; background: {{ $b['secondary_tint'] }};">
                <div class="t-label">{{ $t['drawnOn'] }}</div>
                <div class="b" style="font-size: 10pt; color: #0b1220; margin-top: 1pt;">{{ $c['bank']['name'] }}</div>
                <div style="font-size: 9pt; color: {{ $body }};">{{ $c['bank']['account_name'] }}</div>
                <div style="font-size: 9pt; color: {{ $body }};">{{ collect([$c['bank']['account_number'], $c['bank']['branch']])->filter()->implode(' · ') }}</div>
            </td>
            <td style="width: 1.5%;"></td>
        @endif
        <td class="m-card" style="width: {{ $drawn ? 34 : 50 }}%;">
            <div class="t-label">{{ $t['attachments'] }} · {{ count($doc['attachments']) }}</div>
            @include('vouchers.parts.attachments', ['itemStyle' => 'font-size: 9pt; margin-top: 1pt; color: '.$body.';'])
        </td>
        <td style="width: 1.5%;"></td>
        <td class="m-card">
            <div class="t-label">{{ $t['remarks'] }}</div>
            <div style="font-size: 9.5pt; margin-top: 1pt; color: {{ $body }};">{{ $v['remarks'] ?: '—' }}</div>
        </td>
    </tr>
</table>

{{-- 6 · approvals --}}
<table style="margin-top: 7pt; page-break-after: avoid;">
    <tr>
        <td class="t-label" style="color: #0b1220; font-size: 8.5pt;">{{ $t['approvals'] }}</td>
        <td class="r t-meta">{{ collect($sigs)->where('state', 'done')->count() }} / {{ count($sigs) }}</td>
    </tr>
</table>
<table class="m-auth" style="margin-top: 4pt; border-collapse: separate; border-spacing: 0;">
    @foreach ($sigRows as $row)
        @if (! $loop->first)<tr><td colspan="{{ $perRow * 2 - 1 }}" style="height: 6pt;"></td></tr>@endif
        <tr>
            @foreach ($row as $s)
                @php $pend = $s['state'] === 'pending'; @endphp
                @if (! $loop->first)<td style="width: 2%;"></td>@endif
                <td class="m-appr {{ $pend ? 'm-appr-pending' : '' }} {{ $s['state'] === 'rejected' ? 'm-appr-rejected' : '' }}" style="width: {{ $apW }}%;">
                    <table><tr>
                        <td class="t-label nowrap" style="letter-spacing: .03em; color: {{ $s['state'] === 'rejected' ? '#a3183a' : '#5b6678' }};">{{ $s['caption'] }}</td>
                        <td class="r b nowrap" style="font-size: 8.5pt; color: {{ $b['ink'] }}; padding-left: 4pt;">{{ $s['role'] }}</td>
                    </tr></table>
                    <div style="margin-top: 1pt;">@include('vouchers.parts.signature-mark', ['height' => 34])</div>
                    <div class="m-sigline {{ $pend ? 'm-sigline-pending' : '' }}"></div>
                    <div class="b nowrap" style="font-size: 10pt; color: {{ $s['name'] ? '#0b1220' : '#8a94a6' }};">{{ $s['name'] ?: '—' }}</div>
                    <div class="t-meta" style="{{ $pend ? 'font-style: italic;' : '' }}">{{ $s['meta'] }}</div>
                </td>
            @endforeach
            @for ($i = count($row); $i < $perRow; $i++)<td style="width: 2%;"></td><td style="width: {{ $apW }}%;"></td>@endfor
        </tr>
    @endforeach
</table>

{{-- 7 · footer strip --}}
<div class="m-foot" style="margin-top: 6pt; page-break-inside: avoid;">
    <table>
        <tr>
            <td style="vertical-align: middle; font-size: 8.5pt; color: {{ $body }};">
                @include('vouchers.parts.footer-verify')
                <br><span class="b" style="color: #0b1220;">{{ $v['number'] }}</span> · {{ $t['status'] }}: <span class="b" style="color: #0b1220;">{{ $v['status_label'] }}</span> · {{ $t['generated'] }} {{ $doc['generated_at'] }}
            </td>
            <td class="r" style="width: 84pt; vertical-align: middle; padding-right: 6pt;"><span class="t-label" style="color: {{ $b['ink'] }};">{{ $t['scanToVerify'] }}</span></td>
            <td style="width: {{ $doc['qr'] ? $doc['qr']['size'] * 1.8 + 8 : 1 }}pt; vertical-align: middle;">@include('vouchers.parts.qr', ['cell' => 1.8, 'frameStyle' => 'border-radius: 4pt;'])</td>
        </tr>
    </table>
</div>
@endsection
