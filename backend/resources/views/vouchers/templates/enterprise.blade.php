{{--
  10 · Enterprise — the corporate system document.

  Section order:
    1. Full-width header band in the secondary colour: logo on a white tile,
       company name and contact lines; document title, kind and a large voucher
       number on the right. A primary-colour accent rule closes the band.
    2. Reference strip of five cells: voucher no · date · department (+ cost
       centre) · voucher type · status.
    3. 01 Request — payee, purpose, description | requested by, category,
       reference, remarks; supporting documents run across beneath.
    4. 02 Finance — amount block (total + words) | payment particulars grid
       (every particulars row, two to a line) | drawn-on account + method panel.
    5. 03 Approval workflow — a vertical numbered timeline: circles joined by a
       line, each step with caption · role, name, date, stamp and a signature
       thumbnail. Steps still to come are hollow and grey, "Awaiting …".
    6. Three-column footer: company | footer text | QR, verification code,
       status and generated time.
--}}
@extends('vouchers.layout')

@section('page_margin', '8mm 10mm 7mm')

@php
    $b = $doc['brand']; $t = $doc['t']; $v = $doc['voucher']; $c = $doc['company']; $p = $doc['payment'];
    $rule = '#d3d9e3'; $muted = '#4f5a6d'; $soft = '#6f7a8c'; $ink = '#0b1220'; $wash = '#f5f7fa';
    $sigs = $doc['signatories'];
    $n = count($sigs);
    // Each timeline step has a fixed height so the connecting line meets the
    // next circle exactly; more steps get a little less room each.
    $stepH = $n >= 6 ? 30 : ($n === 5 ? 32 : 33);
    $dot = 17;
    $above = round(($stepH - $dot) / 2, 1);
    $below = $stepH - $dot - $above;
    $bank = $v['kind'] === 'bank' ? $c['bank'] : null;
    $qrCell = 1.8;
    $qrW = $doc['qr'] ? $doc['qr']['size'] * $qrCell + $qrCell * 4 + 2 : 0;
@endphp

@section('styles')
    body { line-height: 1.3; }
    .band { background: {{ $b['secondary'] }}; color: {{ $b['on_secondary'] }}; }
    .band td { vertical-align: middle; }
    .accent { height: 3pt; background: {{ $b['primary'] }}; font-size: 0; line-height: 0; }
    .t-label { color: {{ $muted }}; }
    .strip td { border: .6pt solid {{ $rule }}; border-top: 0; padding: 4pt 8pt 4pt; background: {{ $b['secondary_tint'] }}; vertical-align: top; }
    .strip .val { font-size: 10.5pt; font-weight: bold; margin-top: 1pt; line-height: 1.3; }
    .sec { border-bottom: 1.2pt solid {{ $ink }}; padding-bottom: 2pt; margin-bottom: 5pt; }
    .sec-n { display: inline-block; background: {{ $b['secondary'] }}; color: {{ $b['on_secondary'] }}; font-size: 9pt; font-weight: bold; padding: 1pt 5pt; margin-right: 6pt; }
    .sec-t { font-size: 11pt; font-weight: bold; letter-spacing: .1em; text-transform: uppercase; }
    .kv td { padding: 3.5pt 0; border-bottom: .6pt solid {{ $rule }}; vertical-align: top; line-height: 1.3; }
    .kv td.t-label { padding-top: 5pt; }
    .amount-block { border: .6pt solid {{ $rule }}; border-left: 4pt solid {{ $b['primary'] }}; background: {{ $b['tint'] }}; }
    .panel { border: .6pt solid {{ $rule }}; padding: 5pt 8pt 6pt; }
    .pay { border: .6pt solid {{ $rule }}; }
    .pay td { border-top: .6pt solid {{ $rule }}; padding: 3.5pt 7pt; line-height: 1.3; }
    .pay td.pay-h { background: {{ $b['secondary_tint'] }}; border-top: 0; color: {{ $b['ink'] }}; }
    .pay-v { font-size: 9.5pt; margin-top: 1pt; }
    .tl td { vertical-align: top; }
    .dot { width: {{ $dot }}pt; border-radius: {{ $dot / 2 }}pt; text-align: center; font-size: 8.5pt; font-weight: bold; line-height: 9pt; padding: {{ ($dot - 11.6) / 2 }}pt 0; }
    .seg { border-right: 1.6pt solid {{ $b['primary'] }}; font-size: 0; line-height: 0; }
    .seg-pending { border-right: 1.6pt dashed #b3bac6; }
    .tl td.thumb { border: .6pt solid {{ $rule }}; background: #fff; text-align: center; vertical-align: middle; }
    .foot { font-size: 8.5pt; color: {{ $muted }}; line-height: 1.3; }
@endsection

@section('content')

{{-- Header band --}}
<table class="band">
    <tr>
        <td style="width: 1%; padding: 7pt 10pt 7pt 12pt;">
            <table style="width: auto;"><tr><td style="background: #fff; border-radius: 3pt; padding: 5pt 6pt; vertical-align: middle;">@include('vouchers.parts.logo', ['height' => 38, 'width' => 96])</td></tr></table>
        </td>
        <td style="padding: 7pt 6pt;">
            <div style="font-size: 16pt; font-weight: bold; line-height: 1.2;">{{ $c['name'] }}</div>
            <div style="font-size: 8.5pt; line-height: 1.35; margin-top: 2pt; opacity: .88;">@include('vouchers.parts.company-lines')</div>
            @if ($c['header_text'])<div style="font-size: 8.5pt; margin-top: 1pt;">{{ $c['header_text'] }}</div>@endif
        </td>
        <td class="r" style="width: 36%; padding: 7pt 12pt 7pt 6pt;">
            <div style="font-size: 11pt; font-weight: bold; letter-spacing: .14em; text-transform: uppercase; line-height: 1.3;">{{ $v['type_label'] }}</div>
            <div style="font-size: 8.5pt; letter-spacing: .1em; text-transform: uppercase; opacity: .85;">{{ $v['kind_label'] }}</div>
            <div class="nowrap" style="font-size: 18pt; font-weight: bold; margin-top: 3pt; line-height: 1.2;">{{ $v['number'] }}</div>
        </td>
    </tr>
</table>
<div class="accent"></div>

{{-- Reference strip --}}
<table class="strip">
    <tr>
        <td style="width: 22%;"><div class="t-label">{{ $t['voucherNo'] }}</div><div class="val nowrap">{{ $v['number'] }}</div></td>
        <td style="width: 16%;"><div class="t-label">{{ $t['date'] }}</div><div class="val nowrap">{{ $v['date'] }}</div></td>
        <td style="width: 25%;"><div class="t-label">{{ $t['department'] }}</div><div class="val">{{ $v['department'] }}@if ($v['cost_centre'])<span class="t-meta" style="font-weight: normal;"> · {{ $v['cost_centre'] }}</span>@endif</div></td>
        <td style="width: 20%;"><div class="t-label">{{ $t['voucherType'] }}</div><div class="val">{{ $v['kind_label'] }}</div></td>
        <td style="width: 17%;"><div class="t-label">{{ $t['status'] }}</div><div class="val" style="color: {{ $b['ink'] }};">{{ $v['status_label'] }}</div></td>
    </tr>
</table>

{{-- 01 · Request --}}
<div class="sec" style="margin-top: 7pt;"><span class="sec-n">01</span><span class="sec-t">{{ $t['requestDetails'] }}</span></div>
<table>
    <tr>
        <td style="width: 59%; padding-right: 14pt;">
            <div class="t-label">{{ $t['payee'] }}</div>
            <div style="font-size: 13pt; font-weight: bold; line-height: 1.3;">{{ $v['payee'] }}</div>
            <div class="t-label" style="margin-top: 5pt;">{{ $t['purpose'] }}</div>
            <div class="t-value" style="line-height: 1.3;">{{ $v['purpose'] ?: '—' }}</div>
            @if ($v['description'])<div style="margin-top: 1pt; color: #273246;">{{ $v['description'] }}</div>@endif
            <div style="margin-top: 5pt; border-left: 2.5pt solid {{ $b['primary'] }}; padding: 0 0 0 7pt;">
                <span class="t-label">{{ $t['remarks'] }}</span>&nbsp; {{ $v['remarks'] ?: '—' }}
            </div>
        </td>
        <td style="width: 41%;">
            <table class="kv">
                <tr><td class="t-label" style="width: 36%;">{{ $t['requestedBy'] }}</td><td><span class="b">{{ $v['requester'] }}</span>@if ($v['requester_title'])<div class="t-meta">{{ $v['requester_title'] }}</div>@endif</td></tr>
                <tr><td class="t-label">{{ $t['category'] }}</td><td>{{ $v['category'] }}</td></tr>
                <tr><td class="t-label">{{ $t['reference'] }}</td><td>{{ $v['reference'] ?: '—' }}</td></tr>
                <tr><td class="t-label" style="border-bottom: 0;">{{ $t['attachments'] }}</td><td style="border-bottom: 0;">@include('vouchers.parts.attachments', ['itemStyle' => 'font-size: 9.5pt; line-height: 1.3;'])</td></tr>
            </table>
        </td>
    </tr>
</table>

{{-- 02 · Finance --}}
<div class="sec" style="margin-top: 7pt;"><span class="sec-n">02</span><span class="sec-t">{{ $t['finance'] }}</span></div>
<table>
    <tr>
        <td style="width: {{ $bank ? 50 : 66 }}%; padding-right: 8pt;">
            <table class="amount-block">
                <tr>
                    <td style="width: 1%; white-space: nowrap; padding: 6pt 10pt 7pt 10pt;">
                        <div class="t-label" style="color: {{ $b['ink'] }};">{{ $t['totalPayable'] }}</div>
                        <div class="nowrap" style="margin-top: 2pt; line-height: 1.2;"><span style="font-size: 10pt; font-weight: bold; color: {{ $muted }};">{{ $v['currency'] }}</span> <span style="font-size: 19pt; font-weight: bold;">{{ $v['amount'] }}</span></div>
                    </td>
                    <td style="padding: 6pt 10pt 7pt 8pt; border-left: .6pt solid {{ $rule }};">
                        <div class="t-label">{{ $t['amountWords'] }}</div>
                        <div class="i" style="font-size: 9.5pt; margin-top: 1pt; line-height: 1.35;">{{ $v['amount_words'] }}</div>
                    </td>
                </tr>
            </table>
        </td>
        @if ($bank)
            <td style="width: 31%; padding-right: 8pt;">
                <div class="panel" style="background: {{ $wash }};">
                    <div class="t-label">{{ $t['drawnOn'] }}</div>
                    <div class="b" style="line-height: 1.3;">{{ $bank['name'] }}</div>
                    @if ($bank['account_name'])<div class="t-meta">{{ $bank['account_name'] }}</div>@endif
                    <div class="t-meta">{{ $bank['account_number'] ?: '—' }}@if ($bank['branch']) · {{ $bank['branch'] }}@endif</div>
                </div>
            </td>
        @endif
        <td>
            <div class="panel" style="background: {{ $wash }};">
                <div class="t-label">{{ $t['paymentMethod'] }}</div>
                <div class="b" style="line-height: 1.3;">{{ $v['payment_method'] }}</div>
                <div class="t-meta" style="line-height: 1.35;">{{ $v['kind_label'] }}</div>
            </div>
        </td>
    </tr>
</table>
<table class="pay" style="margin-top: 7pt; border-top: 2pt solid {{ $b['secondary'] }};">
    @foreach (array_chunk($doc['particulars'], 4) as $row)
        <tr>
            @for ($i = 0; $i < 4; $i++)
                <td style="width: {{ [22, 21, 33, 24][$i] }}%; {{ $i ? 'border-left: .6pt solid '.$rule.';' : '' }}">
                    @if (isset($row[$i]))
                        <div class="t-label">{{ $row[$i][0] }}</div>
                        <div class="pay-v" style="{{ $loop->first && $i === 0 ? 'font-weight: bold;' : '' }}">{{ $row[$i][1] }}</div>
                    @endif
                </td>
            @endfor
        </tr>
    @endforeach
</table>

{{-- 03 · Approval workflow — kept whole on one page --}}
<div style="page-break-inside: avoid;">
<div class="sec" style="margin-top: 7pt; margin-bottom: 1pt;"><span class="sec-n">03</span><span class="sec-t">{{ $t['approvalTrail'] }}</span></div>
<table class="tl" style="page-break-inside: avoid;">
    @foreach ($sigs as $s)
        @php
            $pending = $s['state'] === 'pending';
            $rejected = $s['state'] === 'rejected';
            $next = $sigs[$loop->index + 1] ?? null;
            $lineIn = ! $loop->first;
            $lineOut = ! $loop->last;
            $outPending = $next && $next['state'] === 'pending';
            $dotStyle = $pending
                ? 'background: #fff; border: 1.3pt solid #9aa3b2; color: '.$soft.';'
                : ($rejected ? 'background: #a3183a; border: 1.3pt solid #a3183a; color: #fff;' : 'background: '.$b['primary'].'; border: 1.3pt solid '.$b['primary'].'; color: '.$b['on_primary'].';');
            $capColor = $pending ? $soft : ($rejected ? '#a3183a' : $b['ink']);
            $sep = $loop->last ? '' : 'border-bottom: .6pt solid '.$rule.';';
            $top = max(2, $above - 5);
        @endphp
        <tr style="page-break-inside: avoid;">
            <td style="width: {{ $dot + 10 }}pt; height: {{ $stepH }}pt;">
                <table style="width: {{ $dot }}pt; margin-left: 4pt;">
                    <tr><td style="height: {{ $above }}pt; padding: 0;"><table style="width: {{ $dot }}pt;"><tr><td class="{{ $lineIn ? 'seg' : '' }} {{ $lineIn && $pending ? 'seg-pending' : '' }}" style="width: 50%; height: {{ $above }}pt;"></td><td style="width: 50%;"></td></tr></table></td></tr>
                    <tr><td style="padding: 0;"><div class="dot" style="{{ $dotStyle }}">{{ $loop->iteration }}</div></td></tr>
                    <tr><td style="height: {{ $below }}pt; padding: 0;"><table style="width: {{ $dot }}pt;"><tr><td class="{{ $lineOut ? 'seg' : '' }} {{ $lineOut && $outPending ? 'seg-pending' : '' }}" style="width: 50%; height: {{ $below }}pt;"></td><td style="width: 50%;"></td></tr></table></td></tr>
                </table>
            </td>
            <td style="padding: {{ $top }}pt 8pt 0 6pt; width: 37%; {{ $sep }}">
                <div class="t-label" style="color: {{ $capColor }};">{{ $s['caption'] }} · {{ $s['role'] }}</div>
                <div style="font-size: 10.5pt; font-weight: bold; line-height: 1.3; {{ $pending ? 'color: '.$soft.';' : '' }}">{{ $s['name'] ?: '—' }}</div>
            </td>
            <td style="padding: {{ $top }}pt 8pt 0 0; width: 23%; {{ $sep }}">
                <div class="t-label" style="{{ $pending ? 'color: '.$soft.';' : '' }}">{{ $t['date'] }}</div>
                @if ($pending)
                    <div class="i" style="font-size: 9.5pt; line-height: 1.3; color: {{ $soft }};">{{ $s['meta'] }}</div>
                @else
                    <div style="font-size: 9.5pt; line-height: 1.3;">{{ $s['date'] ?: $s['meta'] }}</div>
                @endif
            </td>
            <td style="padding: {{ $top + 4 }}pt 6pt 0 0; width: 15%; {{ $sep }}">
                @if ($s['stamp'])@include('vouchers.parts.stamp', ['kind' => $s['stamp']])@elseif ($pending)<span style="font-size: 7.5pt; font-weight: bold; color: {{ $soft }}; letter-spacing: .1em; text-transform: uppercase; border: 1pt dashed #b3bac6; padding: 1.5pt 5pt;">{{ $t['pending'] }}</span>@endif
            </td>
            <td style="padding: 3pt 0; width: 21%; {{ $sep }}">
                <table><tr><td class="thumb" style="height: {{ $stepH - 7 }}pt; {{ $pending ? 'border-style: dashed; background: '.$wash.';' : '' }}">
                    @if ($s['signature'])<img src="{{ $s['signature'] }}" alt="" style="max-height: {{ $stepH - 11 }}pt; max-width: 96pt;">@else<span style="font-size: 7.5pt; color: {{ $soft }}; letter-spacing: .1em; text-transform: uppercase;">{{ $t['signature'] }}</span>@endif
                </td></tr></table>
            </td>
        </tr>
    @endforeach
</table>
</div>

{{-- Footer --}}
<table style="margin-top: 8pt; border-top: 2.5pt solid {{ $b['secondary'] }}; page-break-inside: avoid;">
    <tr>
        <td class="foot" style="width: 40%; padding: 6pt 10pt 0 0;">
            <div class="b" style="color: {{ $ink }}; font-size: 9.5pt;">{{ $c['name'] }}</div>
            <div>{{ implode(' · ', $c['lines']) }}</div>
        </td>
        <td class="foot" style="width: 24%; padding: 6pt 10pt 0; border-left: .6pt solid {{ $rule }};">
            <div style="color: {{ $ink }};">{{ $c['footer_text'] }}</div>
        </td>
        <td style="width: 36%; padding: 4pt 0 0 10pt; border-left: .6pt solid {{ $rule }};">
            <table>
                <tr>
                    <td style="width: {{ $qrW }}pt; padding-right: 7pt;">@include('vouchers.parts.qr', ['cell' => $qrCell, 'frameStyle' => 'border: .6pt solid '.$rule.';'])</td>
                    <td class="foot" style="vertical-align: middle;">
                        <div class="t-label">{{ $t['scanToVerify'] }}</div>
                        <div class="b" style="font-size: 10.5pt; color: {{ $b['ink'] }}; letter-spacing: .04em;">{{ $v['verification_code'] ?: '—' }}</div>
                        <div style="margin-top: 1pt;">{{ $t['status'] }}: <span class="b" style="color: {{ $ink }};">{{ $v['status_label'] }}</span></div>
                        <div class="nowrap">{{ $t['generated'] }} {{ $doc['generated_at'] }}</div>
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
@endsection
