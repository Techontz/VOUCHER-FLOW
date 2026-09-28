{{--
  05 · Structured Two-Column — request on the left, money on the right.

  Section order:
    1. Full-width header: logo, company name and lines on the left; the
       document title, voucher number, date and bank/cash kind on the right,
       closed by a heavy rule in the secondary colour.
    2. The two-column body, split by a vertical divider, each column opened by
       its own heading:
         LEFT  "Request" — requested by (+ title), department (+ cost centre),
               category, payee, purpose, then the particulars table
               (particulars | amount): the description and reference as the
               line item, closed by the total.
         RIGHT "Payment" — the amount prominent in a tinted block with the
               amount in words, then every payment particular as label/value
               rows (method, voucher type, currency, bank, account name,
               account no., branch, reference, and settlement rows when
               present), drawn on, supporting documents.
    3. Full-width remarks.
    4. A strong full-width approval band: a secondary-colour heading bar,
       then one equal box per signatory under a heavy brand top rule, each
       with caption, signature area (signature + stamp) over a signing line,
       name, and role · meta. Pending boxes keep a grey rule, a dashed line
       and the italic "Awaiting …" meta.
    5. Footer: footer text and verification code on the left; "scan to
       verify", status and generated time beside the QR on the right.
--}}
@extends('vouchers.layout')
@section('page_margin', '9mm 12mm 8mm')

@php
    $b = $doc['brand']; $t = $doc['t']; $v = $doc['voucher']; $c = $doc['company']; $p = $doc['payment'];
    $rule = '#d5dbe5'; $muted = '#4f5b6e';
    $signers = $doc['signatories'];
    $n = max(1, count($signers));
    $boxW = round(100 / $n, 3);
    $qrCell = 1.8;
    $qrW = $doc['qr'] ? $doc['qr']['size'] * $qrCell + 4 * $qrCell : 0;
@endphp

@section('styles')
    .co { font-size: 15pt; font-weight: bold; line-height: 1.2; }
    .co-lines { font-size: 8.5pt; color: {{ $muted }}; line-height: 1.3; margin-top: 1pt; }
    .doc-title { font-size: 11pt; font-weight: bold; letter-spacing: .12em; text-transform: uppercase; color: {{ $b['ink'] }}; }
    .doc-no { font-size: 17pt; font-weight: bold; line-height: 1.15; margin-top: 1pt; }
    .kind { display: inline-block; background: {{ $b['secondary'] }}; color: {{ $b['on_secondary'] }}; font-size: 7.5pt; font-weight: bold; letter-spacing: .1em; text-transform: uppercase; padding: 1.5pt 6pt; }

    .colhead { font-size: 11.5pt; font-weight: bold; letter-spacing: .1em; text-transform: uppercase; color: {{ $b['ink'] }};
               padding-bottom: 4pt; border-bottom: 1.6pt solid {{ $b['primary'] }}; margin-bottom: 2pt; }
    .divider { width: 12pt; border-right: 1pt solid {{ $rule }}; }
    .gap { width: 12pt; }

    .fld td { padding: 5pt 0 4.5pt; border-bottom: .6pt solid {{ $rule }}; vertical-align: top; }
    .fld .v { font-size: 10.5pt; font-weight: bold; margin-top: 1pt; line-height: 1.3; }
    .fld .txt { font-size: 10pt; line-height: 1.4; margin-top: 1pt; }

    .items { margin-top: 9pt; border: .8pt solid {{ $rule }}; }
    .items th { background: {{ $b['secondary_tint'] }}; padding: 4.5pt 7pt; border-bottom: .8pt solid {{ $rule }}; }
    .items td { padding: 5pt 7pt; border-bottom: .6pt solid {{ $rule }}; vertical-align: top; }
    .items .tot td { border-bottom: 0; border-top: 1.4pt solid {{ $b['secondary'] }}; padding: 6pt 7pt; vertical-align: middle; }

    .amt { background: {{ $b['tint'] }}; border-left: 3pt solid {{ $b['primary'] }}; }
    .amt td { padding: 6pt 10pt; }
    .amt .fig { font-size: 19pt; font-weight: bold; color: {{ $b['ink'] }}; line-height: 1.15; margin-top: 2pt; }
    .amt .words { font-size: 9.5pt; font-style: italic; line-height: 1.35; margin-top: 3pt; }

    .pay td { padding: 4pt 0; border-bottom: .6pt solid {{ $rule }}; vertical-align: top; line-height: 1.3; }
    .pay .pv { font-size: 10.5pt; font-weight: bold; margin-top: 1pt; }

    .sub { margin-top: 7pt; }
    .remarks { margin-top: 8pt; border: .8pt solid {{ $rule }}; border-left: 3pt solid {{ $b['secondary'] }}; }
    .remarks td { padding: 6pt 9pt; }

    .band { margin-top: 9pt; page-break-inside: avoid; }
    .band-head td { background: {{ $b['secondary'] }}; color: {{ $b['on_secondary'] }}; padding: 4pt 9pt; font-size: 10pt; font-weight: bold; letter-spacing: .12em; text-transform: uppercase; }
    .sig { page-break-inside: avoid; }
    .sig td.box { border: .8pt solid {{ $rule }}; border-top: 4pt solid {{ $b['primary'] }}; padding: 5pt 6pt 6pt; vertical-align: top; }
    .sig td.box.pending { border-top-color: #b8c0cc; }
    .sig td.box.rejected { border-top-color: #a3183a; }
    .sigline { border-bottom: .8pt solid #0b1220; margin: 2pt 0 4pt; }
    .sigline.pending { border-bottom: .8pt dashed #8a94a6; }

    .foot { margin-top: 8pt; border-top: 1.6pt solid {{ $b['secondary'] }}; }
    .foot td { padding-top: 5pt; vertical-align: top; }
@endsection

@section('content')
{{-- ── 1 · header ── --}}
<table>
    <tr>
        <td style="width: 1%; padding-right: 11pt; vertical-align: middle;">@include('vouchers.parts.logo', ['height' => 46, 'width' => 110])</td>
        <td style="vertical-align: middle;">
            <div class="co">{{ $c['name'] }}</div>
            <div class="co-lines">@include('vouchers.parts.company-lines')</div>
            @if ($c['header_text'])<div class="t-meta" style="margin-top: 2pt;">{{ $c['header_text'] }}</div>@endif
        </td>
        <td style="width: 185pt; vertical-align: middle; text-align: right;">
            <div class="doc-title">{{ $v['type_label'] }}</div>
            <div class="doc-no">{{ $v['number'] }}</div>
            <div style="margin-top: 3pt;">
                <span class="t-label">{{ $t['date'] }}</span>&nbsp; <span class="b" style="font-size: 10.5pt;">{{ $v['date'] }}</span>
            </div>
            <div style="margin-top: 3pt;">
                <span class="kind">{{ $v['kind_label'] }}</span>
            </div>
        </td>
    </tr>
</table>
<div style="border-bottom: 3pt solid {{ $b['secondary'] }}; margin-top: 6pt;"></div>

{{-- ── 2 · the two columns ── --}}
<table style="margin-top: 8pt;">
    <tr>
        {{-- LEFT: the request --}}
        <td style="width: 44%; vertical-align: top;">
            <div class="colhead">{{ $t['requestDetails'] }}</div>
            <table class="fld">
                <tr>
                    <td style="width: 50%; padding-right: 8pt;">
                        <div class="t-label">{{ $t['requestedBy'] }}</div>
                        <div class="v">{{ $v['requester'] }}</div>
                        @if ($v['requester_title'])<div class="t-meta">{{ $v['requester_title'] }}</div>@endif
                    </td>
                    <td>
                        <div class="t-label">{{ $t['department'] }}</div>
                        <div class="v">{{ $v['department'] }}</div>
                        <div class="t-meta">{{ $t['costCentre'] }}: {{ $v['cost_centre'] ?: '—' }}</div>
                    </td>
                </tr>
                <tr>
                    <td style="padding-right: 8pt;">
                        <div class="t-label">{{ $t['category'] }}</div>
                        <div class="v">{{ $v['category'] }}</div>
                    </td>
                    <td>
                        <div class="t-label">{{ $t['payee'] }}</div>
                        <div class="v">{{ $v['payee'] }}</div>
                    </td>
                </tr>
                <tr>
                    <td colspan="2">
                        <div class="t-label">{{ $t['purpose'] }}</div>
                        <div class="v">{{ $v['purpose'] ?: '—' }}</div>
                    </td>
                </tr>
            </table>

            <table class="items">
                <tr>
                    <th class="t-label">{{ $t['particulars'] }}</th>
                    <th class="t-label r nowrap" style="width: 1%;">{{ $t['amount'] }} ({{ $v['currency'] }})</th>
                </tr>
                <tr>
                    <td>
                        <div class="t-label" style="font-size: 7.5pt;">{{ $t['description'] }}</div>
                        <div style="font-size: 10pt; line-height: 1.4;">{{ $v['description'] ?: ($v['purpose'] ?: '—') }}</div>
                        <div class="t-meta" style="margin-top: 2pt;">{{ $t['reference'] }}: <span class="b" style="color: #0b1220;">{{ $v['reference'] ?: '—' }}</span></div>
                    </td>
                    <td class="r b nowrap" style="font-size: 10.5pt;">{{ $v['amount'] }}</td>
                </tr>
                <tr class="tot">
                    <td class="t-label" style="color: #0b1220;">{{ $t['totalPayable'] }}</td>
                    <td class="r b nowrap" style="font-size: 12pt; color: {{ $b['ink'] }};">{{ $v['amount'] }}</td>
                </tr>
            </table>
        </td>

        <td class="divider"></td>
        <td class="gap"></td>

        {{-- RIGHT: the payment --}}
        <td style="vertical-align: top;">
            <div class="colhead">{{ $t['paymentDetails'] }}</div>
            <table class="amt" style="margin-top: 6pt;">
                <tr>
                    <td style="width: 28%; vertical-align: middle; padding-right: 0;">
                        <div class="t-label" style="color: #0b1220;">{{ $t['totalPayable'] }}</div>
                    </td>
                    <td class="r nowrap" style="vertical-align: middle; padding-left: 4pt;"><div class="fig">{{ $v['amount_text'] }}</div></td>
                </tr>
                <tr>
                    <td colspan="2" style="padding-top: 0;">
                        <div class="t-label">{{ $t['amountWords'] }}</div>
                        <div class="words" style="margin-top: 1pt;">{{ $v['amount_words'] }}</div>
                    </td>
                </tr>
            </table>

            {{-- every payment particular (the amount is in the block above), two abreast --}}
            <table class="pay" style="margin-top: 2pt;">
                @foreach (array_chunk(array_slice($doc['particulars'], 1), 2) as $pair)
                    <tr>
                        @foreach ($pair as [$term, $value])
                            <td style="width: 50%;{{ $loop->first ? ' padding-right: 8pt;' : '' }}">
                                <div class="t-label">{{ $term }}</div>
                                <div class="pv">{{ $value }}</div>
                            </td>
                        @endforeach
                        @if (count($pair) === 1)<td></td>@endif
                    </tr>
                @endforeach
            </table>

            <table class="sub">
                <tr>
                    @if ($v['kind'] === 'bank' && $c['bank'])
                        <td style="width: 44%; padding-right: 8pt; font-size: 10pt;">
                            @include('vouchers.parts.bank', ['labelStyle' => 'font-size: 7.5pt; font-weight: bold; letter-spacing: .08em; text-transform: uppercase; color: #5b6678;'])
                        </td>
                    @endif
                    <td>
                        <div class="t-label">{{ $t['attachments'] }}</div>
                        @include('vouchers.parts.attachments', ['itemStyle' => 'font-size: 9pt; line-height: 1.3; margin-top: 1.5pt;'])
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>

{{-- ── 3 · remarks ── --}}
<table class="remarks">
    <tr><td>
        <div class="t-label">{{ $t['remarks'] }}</div>
        <div style="font-size: 10pt; line-height: 1.4; margin-top: 1pt;">{{ $v['remarks'] ?: '—' }}</div>
    </td></tr>
</table>

{{-- ── 4 · approval band ── --}}
<table class="band">
    <tr class="band-head"><td>{{ $t['authorisation'] }}</td></tr>
    <tr><td style="padding-top: 4pt;">
        <table class="sig">
            <tr>
                @foreach ($signers as $s)
                    <td class="box {{ $s['state'] }}" style="width: {{ $boxW }}%;">
                        <div class="t-label" style="color: #0b1220;">{{ $s['caption'] }}</div>
                        @if ($s['state'] === 'pending' && ! $s['signature'])
                            <div style="height: 38pt;"></div>
                        @else
                            @include('vouchers.parts.signature-mark', ['s' => $s, 'height' => 38])
                        @endif
                        <div class="sigline {{ $s['state'] === 'pending' ? 'pending' : '' }}"></div>
                        <div class="b" style="font-size: 10.5pt; line-height: 1.3;">{{ $s['name'] ?: '—' }}</div>
                        <div class="t-meta" style="line-height: 1.3;"><span class="b" style="color: #0b1220;">{{ $s['role'] }}</span> · <span{!! $s['state'] === 'pending' ? ' class="i"' : '' !!}>{{ $s['meta'] }}</span></div>
                    </td>
                    @if (! $loop->last)<td style="width: 5pt; border: 0;"></td>@endif
                @endforeach
            </tr>
        </table>
    </td></tr>
</table>

{{-- ── 5 · footer ── --}}
<table class="foot" style="page-break-inside: avoid;">
    <tr>
        <td style="padding-right: 12pt;">
            <div style="font-size: 9pt; line-height: 1.4;">@include('vouchers.parts.footer-verify')</div>
        </td>
        <td style="width: 1%; white-space: nowrap; text-align: right; padding-right: 6pt;">
            <div class="t-label">{{ $t['scanToVerify'] }}</div>
            <div class="t-meta" style="margin-top: 2pt;">{{ $t['status'] }}: <span class="b" style="color: {{ $b['ink'] }};">{{ $v['status_label'] }}</span></div>
            <div class="t-meta">{{ $t['generated'] }} {{ $doc['generated_at'] }}</div>
        </td>
        <td style="width: {{ $qrW }}pt; padding-top: 2pt;">@include('vouchers.parts.qr', ['cell' => $qrCell])</td>
    </tr>
</table>
@endsection
