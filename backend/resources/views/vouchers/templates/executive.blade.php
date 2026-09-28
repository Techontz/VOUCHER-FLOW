{{--
  04 · Executive — a letter from the board room.

  Serif throughout, everything centred on one axis, generous whitespace and
  colour used only for hairlines. Section order:
    1. Centred identity — logo above the company name in spaced capitals and
       a single centred contact line.
    2. Thin double rule in the secondary colour.
    3. Centred, letter-spaced document title and a "voucher no · date · kind"
       line.
    4. REQUEST SUMMARY — the payee set large, the purpose, the description as a
       paragraph, and requested by / department / category in one line.
    5. FINANCIAL SECTION — the total set large and right-aligned with the
       amount in words; beneath it every payment particular in a quiet
       two-column register (bank, account, branch, reference, currency,
       method…), then the account the voucher is drawn on.
    6. Supporting documents and remarks (italic), side by side.
    7. Signatures — lines side by side with no boxes; the name beneath, the
       caption · role in spaced small capitals and the meta line.
    8. Centred footer under a double rule: footer text, a small QR with the
       verification code, status and generated time.
--}}
@extends('vouchers.layout')
@section('font', 'serif')
@section('page_margin', '9mm 14mm 8mm')

@php
    $b = $doc['brand']; $t = $doc['t']; $v = $doc['voucher']; $c = $doc['company']; $p = $doc['payment'];
    $ink = '#0b1220'; $muted = '#4f5a6b'; $hair = '#c3c9d3';

    // DomPDF draws every line box ~1.28× taller than asked (DejaVu's height ×
    // font_height_ratio 1.1); dividing by that factor for the PDF gives both
    // renderers the same readable leading.
    $lh = fn (float $x) => $doc['mode'] === 'pdf' ? round($x / 1.28, 3) : $x;

    // The register: every particulars row, read down the left column then the right.
    $rows = $doc['particulars'];
    $half = (int) ceil(count($rows) / 2);
    $register = [];
    for ($i = 0; $i < $half; $i++) {
        $register[] = [$rows[$i] ?? null, $rows[$i + $half] ?? null];
    }

    $sigs = $doc['signatories'];
    $sigRows = count($sigs) > 4 ? array_chunk($sigs, 3) : [$sigs];
    $requester = $v['requester'].($v['requester_title'] ? ', '.$v['requester_title'] : '');
    $department = $v['department'].($v['cost_centre'] ? ' ('.$v['cost_centre'].')' : '');
@endphp

@section('styles')
    body { line-height: {{ $lh(1.35) }}; color: {{ $ink }}; }
    .x-caps { text-transform: uppercase; letter-spacing: .22em; }
    .x-lab { font-size: 8pt; text-transform: uppercase; letter-spacing: .16em; color: {{ $muted }}; }
    .x-sec { font-size: 11pt; text-transform: uppercase; letter-spacing: .3em; color: {{ $b['ink'] }}; text-align: center; }
    .x-rule { border-top: .6pt solid {{ $hair }}; height: 0; font-size: 0; line-height: 0; }
    .x-double { border-top: 2.6pt double {{ $b['secondary'] }}; height: 0; font-size: 0; line-height: 0; }
    .x-reg td { padding: 4pt 0; border-bottom: .5pt solid {{ $hair }}; vertical-align: top; }
    .x-reg td.k { font-size: 8.5pt; color: {{ $muted }}; letter-spacing: .04em; width: 17%; }
    .x-reg td.v { font-size: 10pt; width: 30%; text-align: right; padding-right: 0; }
    .x-reg td.gap { border-bottom: 0; width: 6%; }
    .x-sig { page-break-inside: avoid; }
    .x-sig td { vertical-align: top; padding: 0 4pt; }
@endsection

@section('content')
{{-- 1 · centred identity --}}
<table>
    <tr><td class="c">
        <table style="width: auto; margin: 0 auto;"><tr><td>@include('vouchers.parts.logo', ['height' => 46, 'width' => 130])</td></tr></table>
    </td></tr>
    <tr><td class="c x-caps b" style="font-size: 15pt; padding-top: 7pt; letter-spacing: .24em;">{{ $c['name'] }}</td></tr>
    @if ($c['lines'])
        <tr><td class="c t-meta" style="padding-top: 3pt; color: {{ $muted }};">{{ implode(' · ', $c['lines']) }}</td></tr>
    @endif
    @if ($c['header_text'])
        <tr><td class="c i t-meta" style="padding-top: 1pt; color: {{ $ink }};">{{ $c['header_text'] }}</td></tr>
    @endif
</table>

{{-- 2 · double rule --}}
<div class="x-double" style="margin-top: 8pt;"></div>

{{-- 3 · title --}}
<div class="c x-caps" style="font-size: 18pt; letter-spacing: .34em; margin-top: 9pt;">{{ $v['type_label'] }}</div>
<div class="c" style="margin-top: 4pt; font-size: 10.5pt; color: {{ $muted }};">
    <span class="b" style="font-size: 13pt; color: {{ $ink }}; letter-spacing: .04em;">{{ $v['number'] }}</span>
    &nbsp;·&nbsp; {{ $v['date'] }} &nbsp;·&nbsp; <span class="x-caps" style="font-size: 9pt; letter-spacing: .16em;">{{ $v['kind_label'] }}</span>
</div>

{{-- 4 · request summary --}}
<div class="x-sec" style="margin-top: 12pt;">{{ $t['requestDetails'] }}</div>
<table style="margin-top: 5pt;">
    <tr><td>
        <div class="x-lab">{{ $t['payee'] }}</div>
        <div style="font-size: 18pt; margin-top: 0; line-height: {{ $lh(1.3) }};">{{ $v['payee'] }}</div>
        <div class="i" style="font-size: 12pt; margin-top: 2pt;">{{ $v['purpose'] ?: '—' }}</div>
        @if ($v['description'])
            <p style="font-size: 10pt; line-height: {{ $lh(1.45) }}; margin-top: 4pt;">{{ $v['description'] }}</p>
        @endif
        <div style="margin-top: 5pt; font-size: 9.5pt; color: {{ $muted }};">
            <span class="x-lab" style="font-size: 7.5pt; letter-spacing: .08em;">{{ $t['requestedBy'] }}</span>&nbsp; <span style="color: {{ $ink }};">{{ $requester }}</span>
            &nbsp;·&nbsp; <span class="x-lab" style="font-size: 7.5pt; letter-spacing: .08em;">{{ $t['department'] }}</span>&nbsp; <span style="color: {{ $ink }};">{{ $department }}</span>
            &nbsp;·&nbsp; <span class="x-lab" style="font-size: 7.5pt; letter-spacing: .08em;">{{ $t['category'] }}</span>&nbsp; <span style="color: {{ $ink }};">{{ $v['category'] }}</span>
        </div>
    </td></tr>
</table>

{{-- 5 · financial section --}}
<div class="x-sec" style="margin-top: 11pt;">{{ $t['paymentDetails'] }}</div>
<table style="margin-top: 3pt;">
    <tr>
        <td style="vertical-align: bottom; padding-bottom: 3pt;">
            <div class="x-lab">{{ $t['amountWords'] }}</div>
            <div class="i" style="font-size: 11pt; margin-top: 1pt;">{{ $v['amount_words'] }}</div>
        </td>
        <td class="r" style="width: 46%; vertical-align: bottom;">
            <div class="x-lab">{{ $t['totalPayable'] }}</div>
            <div style="line-height: {{ $lh(1.3) }}; margin-top: 1pt;">
                <span style="font-size: 12pt; color: {{ $b['ink'] }}; letter-spacing: .1em;">{{ $v['currency'] }}</span>
                <span class="b" style="font-size: 25pt;">{{ $v['amount'] }}</span>
            </div>
        </td>
    </tr>
</table>
<div style="border-top: 1pt solid {{ $ink }}; margin-top: 4pt;"></div>
<table class="x-reg" style="margin-top: 2pt;">
    @foreach ($register as [$l, $r])
        <tr>
            <td class="k">{{ $l[0] ?? '' }}</td>
            <td class="v {{ $loop->first ? 'b' : '' }}">{{ $l[1] ?? '' }}</td>
            <td class="gap"></td>
            <td class="k">{{ $r[0] ?? '' }}</td>
            <td class="v">{{ $r[1] ?? '' }}</td>
        </tr>
    @endforeach
</table>
@if ($v['kind'] === 'bank' && $c['bank'])
    <div style="margin-top: 6pt; font-size: 9.5pt;">
        <span class="x-lab" style="font-size: 7.5pt; letter-spacing: .08em;">{{ $t['drawnOn'] }}</span>&nbsp;
        {{ $c['bank']['name'] }} · {{ $c['bank']['account_name'] }} · {{ collect([$c['bank']['account_number'], $c['bank']['branch']])->filter()->implode(' · ') }}
    </div>
@endif

{{-- 6 · documents + remarks --}}
<table style="margin-top: 8pt;">
    <tr>
        <td style="width: 48%;">
            <div class="x-lab">{{ $t['attachments'] }}</div>
            <div style="margin-top: 2pt;">@include('vouchers.parts.attachments', ['itemStyle' => 'font-size: 9.5pt; margin-top: 1pt;'])</div>
        </td>
        <td style="width: 4%;"></td>
        <td>
            <div class="x-lab">{{ $t['remarks'] }}</div>
            <div class="i" style="font-size: 10pt; margin-top: 2pt; line-height: {{ $lh(1.4) }};">{{ $v['remarks'] ?: '—' }}</div>
        </td>
    </tr>
</table>

{{-- 7 · signatures --}}
<div style="page-break-inside: avoid;">
    <div class="x-sec" style="margin-top: 12pt;">{{ $t['authorisation'] }}</div>
        @foreach ($sigRows as $row)
        <table class="x-sig" style="margin: {{ $loop->first ? 8 : 12 }}pt auto 0; table-layout: fixed; width: {{ count($row) >= 4 ? 100 : max(36, count($row) * 30) }}%;">
            <tr>
                @foreach ($row as $s)
                    <td style="width: {{ round(100 / count($row), 2) }}%;">
                        @include('vouchers.parts.signature-mark', ['s' => $s, 'height' => 32])
                        <div style="border-top: .8pt solid {{ $s['state'] === 'pending' ? $hair : $ink }}; margin-top: 2pt;"></div>
                        @if ($s['name'])
                            <div class="c b" style="font-size: 10.5pt; margin-top: 3pt; letter-spacing: -.1pt;">{{ $s['name'] }}</div>
                        @else
                            <div class="c" style="font-size: 10.5pt; margin-top: 3pt; color: {{ $muted }};">&nbsp;</div>
                        @endif
                        <div class="c" style="font-size: 7.5pt; color: {{ $b['ink'] }};"><span class="x-caps" style="letter-spacing: .06em;">{{ $s['caption'] }}</span> · {{ $s['role'] }}</div>
                        <div class="c i t-meta" style="color: {{ $muted }};">{{ $s['meta'] }}</div>
                    </td>
                @endforeach
            </tr>
        </table>
    @endforeach
</div>

{{-- 8 · footer --}}
<div style="page-break-inside: avoid;">
    <div class="x-double" style="margin-top: 10pt;"></div>
    <div class="c t-meta i" style="margin-top: 4pt; color: {{ $muted }};">{{ $c['footer_text'] }}</div>
    <table style="margin-top: 2pt;">
        <tr>
            <td class="r t-meta" style="width: 44%; vertical-align: middle; padding-right: 8pt; color: {{ $muted }};">
                {{ $t['status'] }}: <span class="b" style="color: {{ $ink }};">{{ $v['status_label'] }}</span><br>
                {{ $t['generated'] }} {{ $doc['generated_at'] }}
            </td>
            <td style="width: 58pt; vertical-align: middle;">@include('vouchers.parts.qr', ['cell' => 1.8])</td>
            <td class="t-meta" style="vertical-align: middle; padding-left: 8pt; color: {{ $muted }};">
                {{ $t['scanToVerify'] }}<br>
                {{ $t['verificationCode'] }}: <span class="b" style="color: {{ $ink }}; letter-spacing: .06em;">{{ $v['verification_code'] }}</span>
            </td>
        </tr>
    </table>
</div>
@endsection
