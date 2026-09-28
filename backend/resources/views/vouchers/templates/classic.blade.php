{{--
  01 · Classic Corporate — the default, and the client's base design.

  Mirrors the on-screen voucher (web/components/voucher-sheet.tsx) at readable
  print sizes. Section order:
    1. brand rule
    2. header — logo left with company name and contact lines; right: title,
       bank/cash chip, voucher number
    3. heavy rule
    4. four-cell metadata strip — date · department + cost centre ·
       requested by + title · category
    5. two columns — LEFT (~60%): payee, large ruled particulars table
       (particulars | amount) with blank ruled rows, total payable, amount in
       words box; RIGHT (~40%): payment particulars panel (every row), drawn-on
       box, supporting documents box
    6. full-width remarks box
    7. "Authorisation" signature band, one ruled box per signatory
    8. footer — footer text + verification code left; QR + "Scan to verify" right
--}}
@extends('vouchers.layout')

@php
    $b = $doc['brand']; $t = $doc['t']; $v = $doc['voucher']; $c = $doc['company']; $p = $doc['payment'];
    $rule = '#d5dbe5'; $wash = '#f4f6fa'; $body = '#26324a';
    $sigs = $doc['signatories'];
    $perRow = min(4, max(2, count($sigs)));
    $sigRows = array_chunk($sigs, $perRow);
    $isCash = $v['kind'] === 'cash';
    // Payment particulars packed two to a line, in reading order; a long value takes a line of its own.
    $gridRows = []; $pending = null;
    foreach ($doc['particulars'] as $i => $row) {
        $wide = mb_strlen($row[1]) > 20 || mb_strlen($row[0]) > 18;
        if ($wide) { if ($pending) { $gridRows[] = [$pending]; $pending = null; } $gridRows[] = [$row]; continue; }
        if ($pending) { $gridRows[] = [$pending, $row]; $pending = null; } else { $pending = $row; }
    }
    if ($pending) { $gridRows[] = [$pending]; }
    $drawn = ! $isCash && $c['bank'];
    // Blank ruled rows under the line item carry the left column down to the
    // foot of the payment panel, the way a voucher book is printed. DomPDF
    // cannot measure, so both columns are estimated in points; capped modestly.
    $lines = fn (?string $s, int $per) => $s ? (int) ceil(mb_strlen($s) / $per) : 0;
    $rightH = 3 + count($gridRows) * 37 + ($drawn ? 64 : 0) + 30 + max(1, count($doc['attachments'])) * 17;
    $leftH = max(1, $lines($v['payee'], 36)) * 20 + 6 + 22
        + 12 + max(1, $lines($v['purpose'], 28)) * 18 + $lines($v['description'], 32) * 16.7 + ($v['reference'] ? 17 : 0)
        + 42 + 8 + 22 + max(1, $lines($v['amount_words'], 48)) * 18;
    // A floor keeps a short voucher from leaving the foot of the page empty.
    $floor = 350 - (count($sigRows) - 1) * 125 - max(0, $lines($v['remarks'], 80) - 1) * 15 - max(0, collect($c['lines'])->sum(fn ($l) => $lines($l, 50)) - 3) * 14;
    $blankRows = max(1, min(6, (int) round((max($rightH, $floor) - $leftH) / 16)));
@endphp

@section('page_margin', '8mm 12mm 7mm')

@section('styles')
    body { line-height: 1.3; }
    .brandrule { height: 4pt; background: {{ $b['primary'] }}; margin-bottom: 8pt; }
    .c-name { font-size: 15pt; font-weight: bold; letter-spacing: -.2pt; line-height: 1.2; color: #0b1220; }
    .c-lines { font-size: 8.5pt; line-height: 1.3; color: #4a5568; margin-top: 2pt; }
    .c-title { font-size: 13pt; font-weight: bold; letter-spacing: .08em; text-align: right; text-transform: uppercase; color: #0b1220; line-height: 1.3; }
    .c-chip { display: inline-block; border: 1pt solid {{ $isCash ? '#c48a1a' : '#2f6fd0' }}; background: {{ $isCash ? '#fff8ec' : '#eef4ff' }}; color: {{ $isCash ? '#7a4f00' : '#1a4fae' }}; padding: 1.5pt 7pt; border-radius: 2pt; font-size: 8pt; font-weight: bold; letter-spacing: .12em; text-transform: uppercase; }
    .c-number { font-size: 15pt; font-weight: bold; text-align: right; color: #0b1220; line-height: 1.3; }
    .c-hr { border-top: 2pt solid #0b1220; height: 1px; font-size: 0; line-height: 0; }
    .c-meta td { padding: 4pt 8pt 4pt 0; border-bottom: .7pt solid {{ $rule }}; line-height: 1.35; }
    .c-metaval { font-size: 11pt; font-weight: bold; color: #0b1220; margin-top: 1pt; }
    .c-parts { border: .7pt solid {{ $rule }}; }
    .c-parts th { background: {{ $wash }}; border-bottom: .7pt solid {{ $rule }}; padding: 5pt 8pt; }
    .c-parts td { padding: 6pt 8pt; border-bottom: .7pt solid {{ $rule }}; }
    .c-parts td.amt { border-left: .7pt solid {{ $rule }}; }
    .c-parts .blank td { height: 15pt; padding: 0 8pt; }
    .c-parts .total td { border-top: 2pt solid #0b1220; border-bottom: 0; background: {{ $wash }}; padding: 7pt 8pt; vertical-align: middle; }
    .c-words { border: .7pt solid {{ $rule }}; border-left: 3pt solid #0b1220; background: {{ $wash }}; padding: 6pt 9pt; border-radius: 2pt; }
    .c-panel { border: .7pt solid {{ $rule }}; border-radius: 3pt; }
    .c-grid td { padding: 4pt 8pt 4pt; background: #fff; border-bottom: .6pt solid {{ $rule }}; }
    .c-gridval { font-size: 9.5pt; color: #0b1220; }
    .c-gridamt { font-size: 12pt; font-weight: bold; color: #0b1220; }
    .c-drawn { margin-top: -.6pt; border-top: .7pt solid {{ $rule }}; background: {{ $wash }}; padding: 5pt 8pt 6pt; line-height: 1.35; }
    .c-panel-head { background: {{ $wash }}; border-bottom: .7pt solid {{ $rule }}; padding: 5pt 8pt; }
    .c-box { border: .7pt solid {{ $rule }}; border-radius: 3pt; padding: 5pt 8pt; }
    .c-auth { page-break-inside: avoid; }
    .c-auth tr { page-break-inside: avoid; }
    .c-sig { border: .7pt solid {{ $rule }}; border-radius: 3pt; padding: 5pt 7pt 5pt; }
    .c-sig-pending { border-style: dashed; border-color: #b7c0cf; }
    .c-sigline { border-bottom: .8pt solid #0b1220; height: 1px; font-size: 0; line-height: 0; margin: 2pt 0 4pt; }
    .c-sigline-pending { border-bottom: .8pt dashed #8a94a6; }
    .c-foot { font-size: 8.5pt; color: #4a5568; line-height: 1.35; }
@endsection

@section('content')
<div class="brandrule"></div>

{{-- header --}}
<table>
    <tr>
        <td style="width: {{ $c['logo'] ? 118 : 60 }}pt; padding-right: 10pt;">@include('vouchers.parts.logo', ['height' => 48, 'width' => 108])</td>
        <td>
            <div class="c-name">{{ $c['name'] }}</div>
            <div class="c-lines">@include('vouchers.parts.company-lines')</div>
            @if ($c['header_text'])<div style="font-size: 8.5pt; margin-top: 2pt; color: {{ $body }};">{{ $c['header_text'] }}</div>@endif
        </td>
        <td style="width: 175pt;">
            <div class="c-title">{{ $v['type_label'] }}</div>
            <div style="text-align: right; margin-top: 2pt;"><span class="c-chip">{{ $v['kind_label'] }}</span></div>
            <div class="c-number" style="margin-top: 2pt;">{{ $v['number'] }}</div>
        </td>
    </tr>
</table>

<div class="c-hr" style="margin-top: 6pt;"></div>

{{-- metadata strip --}}
<table class="c-meta">
    <tr>
        <td style="width: 22%;"><div class="t-label">{{ $t['date'] }}</div><div class="c-metaval">{{ $v['date'] }}</div></td>
        <td style="width: 26%;"><div class="t-label">{{ $t['department'] }}</div><div class="c-metaval">{{ $v['department'] }}</div>@if ($v['cost_centre'])<div class="t-meta">{{ $t['costCentre'] }} {{ $v['cost_centre'] }}</div>@endif</td>
        <td style="width: 28%;"><div class="t-label">{{ $t['requestedBy'] }}</div><div class="c-metaval">{{ $v['requester'] }}</div>@if ($v['requester_title'])<div class="t-meta">{{ $v['requester_title'] }}</div>@endif</td>
        <td style="width: 24%; padding-right: 0;"><div class="t-label">{{ $t['category'] }}</div><div class="c-metaval">{{ $v['category'] }}</div></td>
    </tr>
</table>

{{-- the substance, payment panel alongside --}}
<table style="margin-top: 8pt;">
    <tr>
        <td style="width: 56%; padding-right: 12pt;">
            <div class="t-label">{{ $t['payee'] }}</div>
            <div style="font-size: 14pt; font-weight: bold; line-height: 1.25; margin: 0 0 6pt; color: #0b1220;">{{ $v['payee'] }}</div>

            <table class="c-parts">
                <tr>
                    <th class="t-label">{{ $t['particulars'] }}</th>
                    <th class="t-label r" style="width: 92pt; border-left: .7pt solid {{ $rule }};">{{ $t['amount'] }} · {{ $v['currency'] }}</th>
                </tr>
                <tr>
                    <td>
                        <div class="b" style="font-size: 11pt; color: #0b1220;">{{ $v['purpose'] ?: '—' }}</div>
                        @if ($v['description'])<div style="margin-top: 3pt; color: {{ $body }};">{{ $v['description'] }}</div>@endif
                        @if ($v['reference'])<div class="t-meta" style="margin-top: 4pt;">{{ $t['reference'] }}: <span class="b" style="color: #0b1220;">{{ $v['reference'] }}</span></div>@endif
                    </td>
                    <td class="amt r b" style="font-size: 11pt; color: #0b1220;">{{ $v['amount'] }}</td>
                </tr>
                @for ($i = 0; $i < $blankRows; $i++)
                    <tr class="blank"><td></td><td class="amt"></td></tr>
                @endfor
                <tr class="total">
                    <td class="t-label" style="font-size: 9pt; color: #0b1220;">{{ $t['totalPayable'] }}</td>
                    <td class="amt r nowrap" style="font-size: 16pt; font-weight: bold; color: #0b1220;">{{ $v['amount'] }}</td>
                </tr>
            </table>

            <div class="c-words" style="margin-top: 8pt;">
                <div class="t-label">{{ $t['amountWords'] }}</div>
                <div class="i" style="font-size: 10.5pt; color: #0b1220; margin-top: 1pt;">{{ $v['amount_words'] }}</div>
            </div>
        </td>

        <td style="width: 44%;">
            <div class="t-label">{{ $t['paymentParticulars'] }}</div>
            <div class="c-panel" style="margin-top: 3pt;">
                {{-- every particulars row, as label-over-value cells two to a line; the amount and any long value take a full line --}}
                <table class="c-grid">
                    @foreach ($gridRows as $gr)
                        <tr>
                            @foreach ($gr as [$term, $value])
                                <td colspan="{{ count($gr) === 1 ? 2 : 1 }}" style="width: {{ count($gr) === 1 ? 100 : 50 }}%; {{ ! $loop->first ? 'border-left: .6pt solid '.$rule.';' : '' }}">
                                    <div class="t-label">{{ $term }}</div>
                                    <div class="{{ $loop->parent->first && $loop->first ? 'c-gridamt' : 'c-gridval' }}">{{ $value }}</div>
                                </td>
                            @endforeach
                        </tr>
                    @endforeach
                </table>
                @if ($drawn)
                    {{-- drawn on: the company account (same fields as parts.bank, set at a readable size) --}}
                    <div class="c-drawn">
                        <div class="t-label">{{ $t['drawnOn'] }}</div>
                        <div style="font-size: 9.5pt; color: #0b1220;"><span class="b">{{ $c['bank']['name'] }}</span>{{ $c['bank']['branch'] ? ' · '.$c['bank']['branch'] : '' }}</div>
                        <div style="font-size: 9.5pt; color: {{ $body }};">{{ collect([$c['bank']['account_number'], $c['bank']['account_name']])->filter()->implode(' · ') }}</div>
                    </div>
                @endif
            </div>

            <div class="c-box" style="margin-top: 6pt;">
                <div class="t-label">{{ $t['attachments'] }}</div>
                @include('vouchers.parts.attachments', ['itemStyle' => 'font-size: 9.5pt; margin-top: 1pt; line-height: 1.3; color: '.$body.';'])
            </div>
        </td>
    </tr>
</table>

{{-- remarks --}}
<table class="c-box" style="margin-top: 8pt; border-collapse: separate;">
    <tr>
        <td class="t-label" style="width: 70pt; padding-top: 1.5pt;">{{ $t['remarks'] }}</td>
        <td style="color: {{ $body }};">{{ $v['remarks'] ?: '—' }}</td>
    </tr>
</table>

{{-- authorisation --}}
@php $colW = round((100 - 2 * ($perRow - 1)) / $perRow, 2); @endphp
<div class="t-label" style="color: #0b1220; font-size: 8.5pt; margin-top: 8pt; padding-bottom: 4pt; page-break-after: avoid;">{{ $t['authorisation'] }}</div>
<table class="c-auth" style="border-collapse: separate; border-spacing: 0;">
    @foreach ($sigRows as $row)
        @if (! $loop->first)<tr><td colspan="{{ $perRow * 2 - 1 }}" style="height: 6pt;"></td></tr>@endif
        <tr>
            @foreach ($row as $s)
                @php $pend = $s['state'] === 'pending'; @endphp
                @if (! $loop->first)<td style="width: 2%;"></td>@endif
                <td class="c-sig {{ $pend ? 'c-sig-pending' : '' }}" style="width: {{ $colW }}%;">
                    <div class="t-label nowrap" style="color: {{ $s['state'] === 'rejected' ? '#a3183a' : '#0b1220' }};">{{ $s['caption'] }}</div>
                    <div>@include('vouchers.parts.signature-mark', ['height' => 34])</div>
                    <div class="c-sigline {{ $pend ? 'c-sigline-pending' : '' }}"></div>
                    <div class="b nowrap" style="font-size: 10pt; color: {{ $s['name'] ? '#0b1220' : '#8a94a6' }};">{{ $s['name'] ?: '—' }}</div>
                    <div class="t-meta"><span class="b" style="color: #26324a;">{{ $s['role'] }}</span> · <span style="{{ $pend ? 'font-style: italic;' : '' }}">{{ $s['meta'] }}</span></div>
                </td>
            @endforeach
            @for ($i = count($row); $i < $perRow; $i++)<td style="width: 2%;"></td><td style="width: {{ $colW }}%;"></td>@endfor
        </tr>
    @endforeach
</table>

{{-- footer --}}
<table style="margin-top: 6pt; border-top: .7pt solid {{ $rule }}; page-break-inside: avoid;">
    <tr>
        <td class="c-foot" style="padding-top: 5pt; vertical-align: bottom;">
            @include('vouchers.parts.footer-verify')
            <br><span class="b" style="color: #0b1220;">{{ $t['status'] }}: {{ $v['status_label'] }}</span> &nbsp;·&nbsp; {{ $t['generated'] }} {{ $doc['generated_at'] }}
        </td>
        <td class="t-meta r" style="width: 70pt; padding: 5pt 6pt 0 0; vertical-align: bottom; color: #0b1220;">{{ $t['scanToVerify'] }}</td>
        <td style="width: {{ $doc['qr'] ? $doc['qr']['size'] * 1.8 + 8 : 1 }}pt; padding-top: 3pt; vertical-align: bottom;">@include('vouchers.parts.qr', ['cell' => 1.8])</td>
    </tr>
</table>
@endsection
