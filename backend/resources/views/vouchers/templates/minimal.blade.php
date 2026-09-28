{{--
  07 · Minimal Professional — quiet, but complete.

  No boxes and no fills: hairline rules, large readable type and generous
  white space carry the hierarchy. One brand accent — the total.

  Section order:
    1. Identity line: small logo + company name left, title / kind right;
       company address and contact lines beneath.
    2. Voucher number set large and light, date and status on the right.
    3. The total, very large, with currency and amount in words — beside the
       payee, purpose and description.
    4. Two quiet columns of label/value rows on hairlines:
       "Request details" (requested by, department, cost centre, category,
       reference, date) and "Payment details" (every particulars row, drawn on).
    5. Supporting documents and remarks as plain text blocks, closing the
       request column (they fill the space beside the longer payment list).
    6. Signatures as bare lines in one row: name, caption · role, meta beneath
       (pending lines read "Awaiting …").
    7. Hairline footer: footer text, verification code, status, generated, QR.
--}}
@extends('vouchers.layout')

@section('page_margin', '10mm 16mm 8mm')

@php
    $b = $doc['brand']; $t = $doc['t']; $v = $doc['voucher']; $c = $doc['company']; $p = $doc['payment'];
    $hair = '#d5dae3'; $muted = '#566074'; $ink = '#0b1220'; $light = '#3f4a5c';

    $request = [
        [$t['requestedBy'], $v['requester'], $v['requester_title']],
        [$t['department'], $v['department'], null],
        [$t['costCentre'], $v['cost_centre'] ?: '—', null],
        [$t['category'], $v['category'], null],
        [$t['reference'], $v['reference'] ?: '—', null],
        [$t['date'], $v['date'], null],
    ];
    $hasBank = $v['kind'] === 'bank' && $c['bank'];

    $sigs = $doc['signatories'];
    $n = max(2, count($sigs));
    $w = round(100 / $n, 2);
    $tight = count($sigs) > 4;
@endphp

@section('styles')
    .lbl { font-size: 8pt; line-height: 1.3; color: {{ $muted }}; letter-spacing: .02em; }
    .cap { font-size: 8pt; line-height: 1.3; font-weight: bold; color: {{ $muted }}; letter-spacing: .14em; text-transform: uppercase; }
    .hair { border-top: .5pt solid {{ $hair }}; height: 0; font-size: 0; line-height: 0; }
    .head { padding-bottom: 5pt; border-bottom: .8pt solid {{ $ink }}; }
    .kv td { padding: 4pt 0 4pt; border-bottom: .5pt solid {{ $hair }}; vertical-align: top; line-height: 1.3; }
    .kv td.k { width: 40%; font-size: 8pt; color: {{ $muted }}; padding-right: 6pt; }
    .kv td.v { font-size: 9.5pt; }
    .sig td.s { vertical-align: top; padding-right: {{ $tight ? 7 : 10 }}pt; }
    .sigline { border-top: .7pt solid {{ $ink }}; padding-top: 4pt; line-height: 1.3; }
    .foot { font-size: 8.5pt; color: {{ $muted }}; line-height: 1.35; }
@endsection

@section('content')

{{-- 1 · Identity --}}
<table>
    <tr>
        <td style="width: 1%; vertical-align: middle;">@include('vouchers.parts.logo', ['height' => 38, 'width' => 96])</td>
        <td style="vertical-align: middle; padding-left: 9pt;">
            <div class="b" style="font-size: 12pt;">{{ $c['name'] }}</div>
        </td>
        <td class="r" style="vertical-align: middle; width: 42%;">
            <div class="b up" style="font-size: 11pt; letter-spacing: .1em;">{{ $v['type_label'] }}</div>
            <div class="t-meta" style="letter-spacing: .06em;">{{ $v['kind_label'] }}</div>
        </td>
    </tr>
</table>
<div class="t-meta" style="margin-top: 4pt; line-height: 1.4; color: {{ $light }};">
    {{ implode('  ·  ', $c['lines']) }}
    @if ($c['header_text'])<br><span class="i">{{ $c['header_text'] }}</span>@endif
</div>

{{-- 2 · The number, large and light --}}
<table style="margin-top: 8pt;">
    <tr>
        <td style="vertical-align: bottom;">
            <div class="lbl">{{ $t['voucherNo'] }}</div>
            <div style="font-size: 24pt; color: {{ $light }}; letter-spacing: -.3pt; line-height: 1.15; margin-top: 1pt;">{{ $v['number'] }}</div>
        </td>
        <td class="r" style="vertical-align: bottom; width: 170pt;">
            <table style="width: auto; margin-left: auto;">
                <tr>
                    <td style="padding: 0 16pt 0 0;"><div class="lbl">{{ $t['date'] }}</div><div class="t-value" style="margin-top: 1pt;">{{ $v['date'] }}</div></td>
                    <td><div class="lbl">{{ $t['status'] }}</div><div class="t-value" style="margin-top: 1pt;">{{ $v['status_label'] }}</div></td>
                </tr>
            </table>
        </td>
    </tr>
</table>

<div class="hair" style="margin-top: 8pt;"></div>

{{-- 3 · The total beside payee, purpose and description --}}
<table style="margin-top: 9pt;">
    <tr>
        <td style="vertical-align: top; width: 52%; padding-right: 18pt;">
            <div class="lbl">{{ $t['totalPayable'] }}</div>
            <div style="margin-top: 4pt; line-height: 1.1;">
                <span style="font-size: 13pt; color: {{ $muted }};">{{ $v['currency'] }}</span>
                <span style="font-size: 32pt; font-weight: bold; color: {{ $b['ink'] }}; letter-spacing: -.6pt;">{{ $v['amount'] }}</span>
            </div>
            <div class="lbl" style="margin-top: 6pt;">{{ $t['amountWords'] }}</div>
            <div class="i" style="font-size: 10.5pt; margin-top: 1pt; line-height: 1.4;">{{ $v['amount_words'] }}</div>
        </td>
        <td style="vertical-align: top; border-left: .5pt solid {{ $hair }}; padding-left: 18pt;">
            <div class="lbl">{{ $t['payee'] }}</div>
            <div class="b" style="font-size: 11.5pt; line-height: 1.3; margin-top: 1pt;">{{ $v['payee'] }}</div>
            <div class="lbl" style="margin-top: 6pt;">{{ $t['purpose'] }}</div>
            <div class="t-value" style="margin-top: 1pt; line-height: 1.3;">{{ $v['purpose'] ?: '—' }}</div>
            @if ($v['description'])
                <div style="font-size: 9.5pt; line-height: 1.3; margin-top: 2pt; color: {{ $light }};">{{ $v['description'] }}</div>
            @endif
        </td>
    </tr>
</table>

{{-- 4 · Two quiet columns --}}
<table style="margin-top: 10pt;">
    <tr>
        <td style="width: 47%; padding-right: 6%;">
            <div class="cap head">{{ $t['requestDetails'] }}</div>
            <table class="kv">
                @foreach ($request as [$k, $val, $sub])
                    <tr>
                        <td class="k">{{ $k }}</td>
                        <td class="v">{{ $val }}@if ($sub)<div class="t-meta">{{ $sub }}</div>@endif</td>
                    </tr>
                @endforeach
            </table>
            {{-- 5 · Documents and remarks, plain text (under the request, beside the longer payment list) --}}
            <div class="cap" style="margin-top: 16pt; margin-bottom: 2pt;">{{ $t['attachments'] }}</div>
            @include('vouchers.parts.attachments', ['itemStyle' => 'font-size: 9.5pt; margin-top: 2pt; line-height: 1.3;'])
            <div class="cap" style="margin-top: 12pt; margin-bottom: 2pt;">{{ $t['remarks'] }}</div>
            <div style="font-size: 9.5pt; line-height: 1.35;">{{ $v['remarks'] ?: '—' }}</div>
        </td>
        <td style="width: 47%;">
            <div class="cap head">{{ $t['paymentDetails'] }}</div>
            <table class="kv">
                @foreach ($doc['particulars'] as [$k, $val])
                    <tr><td class="k">{{ $k }}</td><td class="v {{ $loop->first ? 'b' : '' }}">{{ $val }}</td></tr>
                @endforeach
                @if ($hasBank)
                    <tr>
                        <td class="k">{{ $t['drawnOn'] }}</td>
                        <td class="v">@include('vouchers.parts.bank', ['labelStyle' => 'display: none;'])</td>
                    </tr>
                @endif
            </table>
        </td>
    </tr>
</table>

{{-- 6 · Signatures: a line, a name --}}
<div style="page-break-inside: avoid;">
    <table class="sig" style="margin-top: 14pt; page-break-inside: avoid;">
        <tr style="page-break-inside: avoid;">
            @foreach ($sigs as $s)
                <td class="s" style="width: {{ $w }}%;">
                    @include('vouchers.parts.signature-mark', ['height' => 36, 'align' => 'left'])
                    <div class="sigline">
                        <div class="b" style="font-size: {{ $tight ? 9.5 : 10 }}pt;">{!! $s['name'] ? e($s['name']) : '&nbsp;' !!}</div>
                        <div style="font-size: 8.5pt; margin-top: 1pt;">{{ $s['caption'] }} · {{ $s['role'] }}</div>
                        <div class="t-meta {{ $s['state'] === 'pending' ? 'i' : '' }}" style="margin-top: 1pt;">{{ $s['meta'] }}</div>
                    </div>
                </td>
            @endforeach
            @for ($i = count($sigs); $i < $n; $i++)<td class="s" style="width: {{ $w }}%;"></td>@endfor
        </tr>
    </table>
</div>

{{-- 7 · Footer --}}
<div class="hair" style="margin-top: 10pt;"></div>
<table style="margin-top: 6pt; page-break-inside: avoid;">
    <tr>
        <td class="foot" style="vertical-align: middle; padding-right: 14pt;">
            {{ $c['footer_text'] }}
            <div style="margin-top: 3pt;">{{ $t['status'] }}: <span class="b" style="color: {{ $ink }};">{{ $v['status_label'] }}</span> &nbsp;·&nbsp; {{ $t['generated'] }} {{ $doc['generated_at'] }}</div>
        </td>
        <td class="foot r" style="vertical-align: middle; width: 150pt; padding-right: 6pt;">
            @if ($v['verification_code'])
                <div>{{ $t['verificationCode'] }}</div>
                <div class="b" style="font-size: 10.5pt; color: {{ $ink }}; letter-spacing: .05em;">{{ $v['verification_code'] }}</div>
                <div style="margin-top: 1pt;">{{ $t['scanToVerify'] }}</div>
            @endif
        </td>
        <td style="vertical-align: middle; width: {{ $doc['qr'] ? round($doc['qr']['size'] * 1.8 + 8) : 0 }}pt;">@include('vouchers.parts.qr', ['cell' => 1.8])</td>
    </tr>
</table>
@endsection
