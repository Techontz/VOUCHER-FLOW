{{--
  09 · Modern Split — a coloured side panel and a white working column.

  The page is one table row of two cells. The LEFT PANEL (~31%) is filled with
  the secondary colour from top to bottom and carries the identity and the
  voucher's facts, in this order: logo on a white tile, company name and
  contact lines, document title + kind, voucher number (large), date, status,
  department (+ cost centre), requested by (+ title), category, reference —
  and, pinned to the foot of the panel, the verification QR on a white tile
  with its code.

  The MAIN COLUMN (white) reads top to bottom:
    1. Payee + purpose heading
    2. Particulars table (purpose, description, reference | amount) with total
    3. Amount block on the brand tint — total payable + amount in words
    4. Payment details — every particulars row in two ruled columns, then the
       account the voucher is drawn on
    5. Supporting documents | remarks
    6. Approvals — a grid of blocks (2 per row, 3 when there are 5–6);
       pending blocks are dashed with "Awaiting …"
    7. Footer line — footer text, status, generated time
--}}
@extends('vouchers.layout')

@section('page_margin', '5mm 7mm 5mm 6mm')

@php
    $b = $doc['brand']; $t = $doc['t']; $v = $doc['voucher']; $c = $doc['company']; $p = $doc['payment'];
    $rule = '#d6dce6'; $muted = '#4f5a6d'; $soft = '#6f7a8c'; $ink = '#0b1220';
    $bank = $v['kind'] === 'bank' ? $c['bank'] : null;
    $pairs = array_chunk($doc['particulars'], 2);
    $sigs = $doc['signatories'];
    $perRow = 2;
    $sigRows = array_chunk($sigs, $perRow);
    // The sheet is 297mm tall less 10mm of page margin. The split table is
    // held at that height so the panel runs the full page, and the panel's
    // own two rows are sized so the QR sits at its foot.
    $pageH = 806;
    $qrH = 122;
    // DomPDF sizes a cell's height without its padding; a browser (border-box) includes it.
    $pdf = $doc['mode'] === 'pdf';
    $padTop = $pdf ? 16 : 0;
    $padBottom = $pdf ? 14 : 0;
@endphp

@section('styles')
    body { line-height: 1.3; }
    .split { height: {{ $pageH }}pt; table-layout: fixed; }
    .panel { background: {{ $b['secondary'] }}; color: {{ $b['on_secondary'] }}; width: 30%; }
    .p-label { font-size: 7.5pt; font-weight: bold; letter-spacing: .1em; text-transform: uppercase; opacity: .72; }
    .p-val { font-size: 10pt; font-weight: bold; line-height: 1.3; margin-top: 1pt; }
    .p-sub { font-size: 8.5pt; opacity: .82; line-height: 1.3; }
    .p-item { padding-top: 8pt; }
    .p-rule { border-top: .8pt solid {{ $b['on_secondary'] }}; opacity: .25; height: 0; font-size: 0; line-height: 0; margin: 11pt 0 1pt; }
    .main { padding-left: 15pt; font-size: 9.5pt; }
    .t-label { color: {{ $muted }}; }
    .h-sec { font-size: 11pt; font-weight: bold; color: {{ $ink }}; padding-bottom: 3pt; border-bottom: 1.4pt solid {{ $b['primary'] }}; margin-bottom: 1pt; }
    .h-min { color: {{ $ink }}; padding-bottom: 3pt; border-bottom: 1.4pt solid {{ $b['primary'] }}; }
    .items th { background: {{ $b['secondary_tint'] }}; padding: 4pt 8pt; border-bottom: .8pt solid {{ $rule }}; }
    .items td { padding: 4pt 8pt; border-bottom: .6pt solid {{ $rule }}; line-height: 1.35; }
        .items tr.amount td { background: {{ $b['tint'] }}; border-bottom: 0; }
    .pd { table-layout: fixed; }
    .pd td { padding: 3pt 5pt; line-height: 1.3; vertical-align: top; }
    .pd tr.z td { background: #f3f5f8; }
    .pd td.k { width: 23%; font-size: 8pt; font-weight: bold; color: {{ $muted }}; padding-top: 5pt; }
    .pd td.v { width: 27%; font-size: 9.5pt; }
    .sig { border: .8pt solid {{ $rule }}; border-left: 3pt solid {{ $b['primary'] }}; padding: 4pt 8pt 4pt 9pt; }
    .sig-pending { border: .9pt dashed #a9b1bf; border-left: 3pt solid #c9ced8; background: #fafbfc; }
    .sig-line { border-top: .8pt solid {{ $ink }}; margin-top: 2pt; padding-top: 3pt; }
@endsection

@section('content')
<table class="split">
    <tr>
        {{-- ─────────── LEFT PANEL: identity and the voucher's facts ─────────── --}}
        <td class="panel" style="padding: 0;">
          <table>
            <tr><td style="height: {{ $pageH - $qrH - $padTop }}pt; padding: 16pt 14pt 0; vertical-align: top;">
            <table style="width: auto;"><tr><td style="background: #fff; border-radius: 3pt; padding: 6pt 7pt; vertical-align: middle;">@include('vouchers.parts.logo', ['height' => 44, 'width' => 110])</td></tr></table>
            <div style="font-size: 13pt; font-weight: bold; line-height: 1.25; margin-top: 9pt;">{{ $c['name'] }}</div>
            <div class="p-sub" style="margin-top: 3pt; line-height: 1.4;">@include('vouchers.parts.company-lines')</div>
            @if ($c['header_text'])<div class="p-sub" style="margin-top: 3pt;">{{ $c['header_text'] }}</div>@endif

            <div class="p-rule"></div>
            <div style="font-size: 13pt; font-weight: bold; letter-spacing: .06em; text-transform: uppercase; line-height: 1.25; margin-top: 8pt;">{{ $v['type_label'] }}</div>
            <div class="p-sub" style="letter-spacing: .08em; text-transform: uppercase;">{{ $v['kind_label'] }}</div>

            <div class="p-item" style="padding-top: 10pt;">
                <div class="p-label">{{ $t['voucherNo'] }}</div>
                <div style="font-size: 14pt; font-weight: bold; line-height: 1.25;" class="nowrap">{{ $v['number'] }}</div>
            </div>
            <div class="p-item">
                <div class="p-label">{{ $t['date'] }}</div>
                <div class="p-val">{{ $v['date'] }}</div>
            </div>
            <div class="p-item">
                <div class="p-label">{{ $t['status'] }}</div>
                <div style="margin-top: 3pt;"><span style="display: inline-block; background: {{ $b['primary'] }}; color: {{ $b['on_primary'] }}; font-size: 8.5pt; font-weight: bold; letter-spacing: .08em; text-transform: uppercase; padding: 2pt 7pt; border-radius: 2pt;">{{ $v['status_label'] }}</span></div>
            </div>

            <div class="p-rule"></div>
            <div class="p-item">
                <div class="p-label">{{ $t['department'] }}</div>
                <div class="p-val">{{ $v['department'] }}</div>
                @if ($v['cost_centre'])<div class="p-sub">{{ $t['costCentre'] }} · {{ $v['cost_centre'] }}</div>@endif
            </div>
            <div class="p-item">
                <div class="p-label">{{ $t['requestedBy'] }}</div>
                <div class="p-val">{{ $v['requester'] }}</div>
                @if ($v['requester_title'])<div class="p-sub">{{ $v['requester_title'] }}</div>@endif
            </div>
            <div class="p-item">
                <div class="p-label">{{ $t['category'] }}</div>
                <div class="p-val">{{ $v['category'] }}</div>
            </div>
            <div class="p-item">
                <div class="p-label">{{ $t['reference'] }}</div>
                <div class="p-val">{{ $v['reference'] ?: '—' }}</div>
            </div>
            </td></tr>
            {{-- Foot of the panel: the verification QR --}}
            <tr><td style="height: {{ $qrH - $padBottom }}pt; padding: 0 14pt 14pt; vertical-align: bottom;">
                @php $qrW = $doc['qr'] ? $doc['qr']['size'] * 2.2 + 8.8 + 6 : 0; @endphp
                <table style="width: {{ $qrW }}pt;"><tr><td style="width: {{ $qrW }}pt; background: #fff; border-radius: 3pt; padding: 3pt;">@include('vouchers.parts.qr', ['cell' => 2.2])</td></tr></table>
                <div class="p-label" style="margin-top: 6pt;">{{ $t['scanToVerify'] }}</div>
                <div style="font-size: 10.5pt; font-weight: bold; letter-spacing: .04em;">{{ $v['verification_code'] ?: '—' }}</div>
            </td></tr>
          </table>
        </td>

        {{-- ─────────── MAIN COLUMN ─────────── --}}
        <td class="main" style="width: 70%;">
            {{-- 1 · Payee + purpose --}}
            <div class="t-label" style="line-height: 1.2;">{{ $t['payee'] }}</div>
            <div style="font-size: 16pt; font-weight: bold; line-height: 1.2; color: {{ $ink }};">{{ $v['payee'] }}</div>
            <div style="font-size: 11pt; color: {{ $b['ink'] }}; font-weight: bold; margin-top: 3pt; line-height: 1.3;">{{ $v['purpose'] ?: '—' }}</div>

            {{-- 2 · Particulars, closed by 3 · the amount block (total + words on the brand tint) --}}
            <table class="items" style="margin-top: 10pt; border: .6pt solid {{ $rule }};">
                <tr>
                    <th class="t-label">{{ $t['particulars'] }}</th>
                    <th class="t-label r" style="width: 26%;">{{ $t['amount'] }} ({{ $v['currency'] }})</th>
                </tr>
                <tr>
                    <td>
                        <div class="b">{{ $v['purpose'] ?: '—' }}</div>
                        @if ($v['description'])<div style="margin-top: 1pt; color: #273246;">{{ $v['description'] }}</div>@endif
                        <div class="t-meta" style="margin-top: 2pt;">{{ $t['reference'] }}: {{ $v['reference'] ?: '—' }}</div>
                    </td>
                    <td class="r" style="font-size: 10.5pt; font-weight: bold;">{{ $v['amount'] }}</td>
                </tr>
                <tr class="amount">
                    <td style="border-top: 1.4pt solid {{ $ink }}; border-left: 4pt solid {{ $b['primary'] }}; padding: 7pt 10pt 8pt;">
                        <div class="t-label">{{ $t['amountWords'] }}</div>
                        <div class="i" style="font-size: 10pt; line-height: 1.3;">{{ $v['amount_words'] }}</div>
                    </td>
                    <td class="r nowrap" style="border-top: 1.4pt solid {{ $ink }}; padding: 7pt 10pt 8pt 6pt; vertical-align: middle;">
                        <div class="t-label" style="color: {{ $b['ink'] }};">{{ $t['totalPayable'] }}</div>
                        <div style="line-height: 1.15;"><span style="font-size: 9.5pt; font-weight: bold; color: {{ $muted }};">{{ $v['currency'] }}</span> <span style="font-size: 19pt; font-weight: bold; color: {{ $ink }};">{{ $v['amount'] }}</span></div>
                    </td>
                </tr>
            </table>

            {{-- 4 · Payment details --}}
            <div class="h-sec" style="margin-top: 8pt;">{{ $t['paymentDetails'] }}</div>
            <table class="pd" style="margin-top: 3pt;">
                @foreach ($pairs as $pair)
                    <tr class="{{ $loop->odd ? 'z' : '' }}">
                        @foreach ($pair as [$term, $value])
                            <td class="k" style="width: {{ $loop->first ? 24 : 20 }}%;">{{ $term }}</td>
                            <td class="v" style="width: {{ $loop->first ? 26 : 30 }}%; {{ $loop->parent->first && $loop->first ? 'font-weight: bold;' : '' }}">{{ $value }}</td>
                        @endforeach
                        @if (count($pair) === 1)<td class="k" style="width: 20%;"></td><td class="v" style="width: 30%;"></td>@endif
                    </tr>
                @endforeach
            </table>
            @if ($bank)
                <table style="margin-top: 6pt; background: {{ $b['secondary_tint'] }};">
                    <tr>
                        <td class="t-label" style="width: 1%; white-space: nowrap; padding: 6pt 10pt 5pt 9pt;">{{ $t['drawnOn'] }}</td>
                        <td style="padding: 5pt 9pt 5pt 0; line-height: 1.3;"><span class="b">{{ $bank['name'] }}</span>@if ($bank['account_name']) · {{ $bank['account_name'] }}@endif<span class="t-meta"> · {{ collect([$bank['account_number'], $bank['branch']])->filter()->implode(' · ') }}</span></td>
                    </tr>
                </table>
            @endif

            {{-- 5 · Documents | remarks --}}
            <table style="margin-top: 8pt;">
                <tr>
                    <td style="width: 50%; padding-right: 9pt;">
                        <div class="t-label h-min">{{ $t['attachments'] }}</div>
                        <div style="padding-top: 2pt;">@include('vouchers.parts.attachments', ['itemStyle' => 'font-size: 9.5pt; line-height: 1.3; margin-top: 1pt;'])</div>
                    </td>
                    <td style="width: 50%; padding-left: 9pt;">
                        <div class="t-label h-min">{{ $t['remarks'] }}</div>
                        <div style="padding-top: 3pt;">{{ $v['remarks'] ?: '—' }}</div>
                    </td>
                </tr>
            </table>

            {{-- 6 · Approvals — never split across pages --}}
            <div style="page-break-inside: avoid;">
                <div class="h-sec" style="margin-top: 8pt; margin-bottom: 5pt;">{{ $t['approvals'] }}</div>
                <table style="page-break-inside: avoid;">
                    @foreach ($sigRows as $row)
                        <tr style="page-break-inside: avoid;">
                            @for ($i = 0; $i < $perRow; $i++)
                                @php $s = $row[$i] ?? null; @endphp
                                <td style="width: {{ round(100 / $perRow, 2) }}%; padding: {{ $loop->first ? 0 : 6 }}pt {{ $i < $perRow - 1 ? 4 : 0 }}pt 0 {{ $i > 0 ? 4 : 0 }}pt;">
                                    @if ($s)
                                        @php $pending = $s['state'] === 'pending'; $rejected = $s['state'] === 'rejected'; @endphp
                                        <div class="sig {{ $pending ? 'sig-pending' : '' }}" style="{{ $rejected ? 'border-left-color: #a3183a;' : '' }}">
                                            <div class="t-label" style="color: {{ $pending ? $soft : ($rejected ? '#a3183a' : $b['ink']) }};">{{ $s['caption'] }} · {{ $s['role'] }}</div>
                                            <table style="border-bottom: .8pt {{ $pending ? 'dashed #a9b1bf' : 'solid '.$ink }};"><tr>
                                                <td style="height: 19pt; vertical-align: bottom; padding-bottom: 1pt;">@if ($s['signature'])<img src="{{ $s['signature'] }}" alt="" style="max-height: 18pt; max-width: 90pt;">@endif</td>
                                                <td class="r" style="vertical-align: bottom; padding-bottom: 3pt;">@if ($s['stamp'])@include('vouchers.parts.stamp', ['kind' => $s['stamp']])@endif</td>
                                            </tr></table>
                                            <div style="font-size: 10pt; font-weight: bold; line-height: 1.3; margin-top: 3pt; {{ $pending ? 'color: '.$soft.';' : '' }}">{{ $s['name'] ?: '—' }}</div>
                                            <div class="t-meta {{ $pending ? 'i' : '' }}" style="{{ $pending ? '' : 'color: '.$ink.';' }}">{{ $s['meta'] }}</div>
                                        </div>
                                    @endif
                                </td>
                            @endfor
                        </tr>
                    @endforeach
                </table>
            </div>

            {{-- 7 · Footer --}}
            <table style="margin-top: 9pt; border-top: .8pt solid {{ $rule }}; page-break-inside: avoid;">
                <tr>
                    <td class="t-meta" style="padding-top: 5pt; padding-right: 10pt; color: {{ $ink }}; line-height: 1.35;">{{ $c['footer_text'] }}</td>
                    <td class="t-meta r" style="width: 40%; padding-top: 5pt; line-height: 1.35;">
                        {{ $t['status'] }}: <span class="b" style="color: {{ $ink }};">{{ $v['status_label'] }}</span><br>
                        {{ $t['generated'] }} {{ $doc['generated_at'] }}
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
@endsection
