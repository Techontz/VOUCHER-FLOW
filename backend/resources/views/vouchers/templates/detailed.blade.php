{{--
  06 · Detailed Business — everything on record, nothing crowded.

  For companies that need a lot of information on the voucher. A letterhead
  with a boxed identity panel on the right (document title bar, voucher no.,
  date, bank/cash kind), then five numbered sections, each opened by a
  full-width header bar in the secondary colour with the number in a
  primary-colour cell:

    1 Request      — requested by, job title, department, cost centre, date,
                     category, status, bank/cash kind (two pairs per row)
    2 Expense      — payee, purpose, description, then a particulars table
                     (# | particulars | reference | amount) with the total and
                     the amount in words, then remarks
    3 Payment      — every payment particular as a two-pairs-per-row table,
                     then the account it is drawn on
    4 Supporting documents — a numbered list
    5 Authorisation — one table row per signatory: caption · role | name |
                     date | signature + stamp; pending rows read "Awaiting …"

  Footer: footer text and verification code, status and generated time, and
  the QR. Generous row heights; label cells carry a light secondary wash.
--}}
@extends('vouchers.layout')
@section('page_margin', '6mm 11mm 6mm')

@php
    $b = $doc['brand']; $t = $doc['t']; $v = $doc['voucher']; $c = $doc['company']; $p = $doc['payment'];
    $rule = '#d3d9e3';
    $qrCell = 1.8;
    $qrW = $doc['qr'] ? $doc['qr']['size'] * $qrCell + 4 * $qrCell : 0;
    // Every payment particular, then the company account it is drawn on, as
    // cells laid two pairs to a row.
    $payCells = array_map(fn ($r) => ['term' => $r[0], 'value' => $r[1], 'drawn' => false], $doc['particulars']);
    if ($v['kind'] === 'bank' && $c['bank']) {
        $payCells[] = ['term' => $t['drawnOn'], 'value' => $c['bank']['name'], 'drawn' => true];
    }
    $payPairs = array_chunk($payCells, 2);
    $docs = $doc['attachments'];
@endphp

@section('styles')
    .co { font-size: 14pt; font-weight: bold; line-height: 1.25; }
    .co-lines { font-size: 8.5pt; color: #4f5b6e; line-height: 1.3; margin-top: 1pt; }

    .idbox { border: 1pt solid {{ $b['secondary'] }}; }
    .idbox td { padding: 2.5pt 8pt; vertical-align: middle; line-height: 1.3; }
    .idbox td.top { background: {{ $b['secondary'] }}; color: {{ $b['on_secondary'] }}; font-size: 10.5pt; font-weight: bold;
                    letter-spacing: .12em; text-transform: uppercase; text-align: center; padding: 4pt 8pt; }

    .sec { margin-top: 2pt; }
    .bar td { background: {{ $b['secondary'] }}; color: {{ $b['on_secondary'] }}; padding: 1.5pt 9pt; line-height: 1.3; vertical-align: middle;
              font-size: 11pt; font-weight: bold; letter-spacing: .1em; text-transform: uppercase; }
    .bar td.num { width: 24pt; text-align: center; background: {{ $b['primary'] }}; color: {{ $b['on_primary'] }}; font-size: 11pt; letter-spacing: 0; padding: 1.5pt 0; }

    .grid { border: .8pt solid {{ $rule }}; border-top: 0; }
    .grid td { padding: 4pt 9pt; border-right: .6pt solid {{ $rule }}; border-bottom: .6pt solid {{ $rule }}; vertical-align: top; line-height: 1.3; }
    .grid td.end { border-right: 0; }
    .grid tr.last td { border-bottom: 0; }
    .grid .gv { font-size: 10pt; margin-top: 1pt; }
    .kv { border: .8pt solid {{ $rule }}; border-top: 0; }
    .kv td { padding: 4pt 9pt; border-bottom: .6pt solid {{ $rule }}; vertical-align: middle; line-height: 1.3; }
    .kv td.l { width: 16%; white-space: nowrap; background: {{ $b['secondary_tint'] }}; border-right: .6pt solid {{ $rule }}; }
    .kv td.v { width: 34%; font-size: 10pt; }
    .kv td.v2 { border-right: .6pt solid {{ $rule }}; }
    .kv tr.last td { border-bottom: 0; }

    .items { border: .8pt solid {{ $rule }}; border-top: 0; }
    .items th { background: {{ $b['secondary_tint'] }}; padding: 4pt 9pt; border-bottom: .8pt solid {{ $rule }}; }
    .items td { padding: 4pt 9pt; border-bottom: .6pt solid {{ $rule }}; vertical-align: top; line-height: 1.35; }
    .items tr.total td { background: {{ $b['tint'] }}; border-top: 1.2pt solid {{ $b['primary'] }}; vertical-align: middle; padding: 4pt 9pt; }

    .auth { border: .8pt solid {{ $rule }}; border-top: 0; page-break-inside: avoid; }
    .auth th { background: {{ $b['secondary_tint'] }}; padding: 4pt 8pt; border-bottom: .8pt solid {{ $rule }}; }
    .auth td { padding: 4pt 8pt; border-bottom: .6pt solid {{ $rule }}; vertical-align: middle; line-height: 1.3; height: 22pt; }
    .auth tr { page-break-inside: avoid; }

    .foot { margin-top: 4pt; border-top: 1.4pt solid {{ $b['secondary'] }}; page-break-inside: avoid; }
    .foot td { padding-top: 4pt; vertical-align: top; }
@endsection

@section('content')
{{-- ── letterhead + identity panel ── --}}
<table>
    <tr>
        <td style="width: 1%; padding-right: 9pt; vertical-align: middle;">@include('vouchers.parts.logo', ['height' => 40, 'width' => 78])</td>
        <td style="vertical-align: middle; padding-right: 8pt;">
            <div class="co">{{ $c['name'] }}</div>
            <div class="co-lines">@include('vouchers.parts.company-lines')</div>
            @if ($c['header_text'])<div class="t-meta" style="margin-top: 2pt;">{{ $c['header_text'] }}</div>@endif
        </td>
        <td style="width: 162pt; vertical-align: middle;">
            <table class="idbox">
                <tr><td colspan="2" class="top">{{ $v['type_label'] }}</td></tr>
                <tr>
                    <td class="t-label nowrap" style="padding-top: 4pt; letter-spacing: .04em; padding-right: 0;">{{ $t['voucherNo'] }}</td>
                    <td class="r b nowrap" style="font-size: 12pt; padding-top: 4pt;">{{ $v['number'] }}</td>
                </tr>
                <tr>
                    <td class="nowrap" style="padding-bottom: 4pt;"><span class="t-label">{{ $t['date'] }}</span>&nbsp; <span class="b" style="font-size: 10.5pt;">{{ $v['date'] }}</span></td>
                    <td class="r b nowrap" style="font-size: 10pt; padding-bottom: 4pt; color: {{ $b['ink'] }};">{{ $v['kind_label'] }}</td>
                </tr>
            </table>
        </td>
    </tr>
</table>
<div style="border-top: 2.4pt solid {{ $b['primary'] }}; margin-top: 4pt;"></div>

{{-- ── 1 · Request ── --}}
<div class="sec">
    <table class="bar"><tr><td class="num">1</td><td>{{ $t['requestDetails'] }}</td></tr></table>
    <table class="grid">
        <tr class="last">
            <td style="width: 24%;"><div class="t-label">{{ $t['requestedBy'] }}</div><div class="gv b" style="font-size: 10.5pt;">{{ $v['requester'] }}</div><div class="t-meta">{{ $v['requester_title'] ?: '—' }}</div></td>
            <td style="width: 24%;"><div class="t-label">{{ $t['department'] }}</div><div class="gv b">{{ $v['department'] }}</div><div class="t-meta">{{ $t['costCentre'] }}: {{ $v['cost_centre'] ?: '—' }}</div></td>
            <td style="width: 17%;"><div class="t-label">{{ $t['date'] }}</div><div class="gv">{{ $v['date'] }}</div></td>
            <td style="width: 19%;"><div class="t-label">{{ $t['category'] }}</div><div class="gv">{{ $v['category'] }}</div></td>
            <td class="end"><div class="t-label">{{ $t['status'] }}</div><div class="gv b" style="color: {{ $b['ink'] }};">{{ $v['status_label'] }}</div></td>
        </tr>
    </table>
</div>

{{-- ── 2 · Expense ── --}}
<div class="sec">
    <table class="bar"><tr><td class="num">2</td><td>{{ $t['expenseDetails'] }}</td></tr></table>
    <table class="kv">
        <tr class="last">
            <td class="l t-label">{{ $t['payee'] }}</td><td class="v v2 b" style="font-size: 10.5pt;">{{ $v['payee'] }}</td>
            <td class="l t-label">{{ $t['remarks'] }}</td><td class="v">{{ $v['remarks'] ?: '—' }}</td>
        </tr>
    </table>
    <table class="items">
        <tr>
            <th class="t-label" style="width: 6%; border-top: .8pt solid {{ $rule }};">#</th>
            <th class="t-label" colspan="2" style="border-top: .8pt solid {{ $rule }};">{{ $t['purpose'] }} &nbsp;/&nbsp; {{ $t['description'] }}</th>
            <th class="t-label r nowrap" style="width: 22%; border-top: .8pt solid {{ $rule }};">{{ $t['amount'] }} ({{ $v['currency'] }})</th>
        </tr>
        <tr>
            <td class="b">1</td>
            <td colspan="2">
                <div class="b">{{ $v['purpose'] ?: $v['category'] }}</div>
                <div style="font-size: 9.5pt; margin-top: 1pt;">{{ $v['description'] ?: '—' }}</div>
            </td>
            <td class="r nowrap">
                <div class="b" style="font-size: 10.5pt;">{{ $v['amount'] }}</div>
                <div class="t-meta" style="margin-top: 2pt;">{{ $t['reference'] }}</div>
                <div class="b" style="font-size: 9.5pt;">{{ $v['reference'] ?: '—' }}</div>
            </td>
        </tr>
        <tr class="total">
            <td colspan="3" style="border-bottom: 0; vertical-align: middle;">
                <span class="t-label">{{ $t['amountWords'] }}:</span>&nbsp; <span class="i" style="font-size: 10pt;">{{ $v['amount_words'] }}</span>
            </td>
            <td class="r nowrap" style="border-bottom: 0;">
                <div class="t-label" style="color: #0b1220;">{{ $t['totalPayable'] }}</div>
                <div class="b" style="font-size: 16pt; line-height: 1.2; color: {{ $b['ink'] }};">{{ $v['amount_text'] }}</div>
            </td>
        </tr>
    </table>
</div>

{{-- ── 3 · Payment ── --}}
<div class="sec">
    <table class="bar"><tr><td class="num">3</td><td>{{ $t['paymentParticulars'] }}</td></tr></table>
    <table class="kv">
        @foreach ($payPairs as $pair)
            <tr class="{{ $loop->last ? 'last' : '' }}">
                @foreach ([0, 1] as $i)
                    @php $cell = $pair[$i] ?? null; @endphp
                    <td class="l t-label">{{ $cell['term'] ?? '' }}</td>
                    <td class="v b{{ $i === 0 ? ' v2' : '' }}"{!! ($loop->parent->first && $i === 0) ? ' style="font-size: 10.5pt; color: '.$b['ink'].';"' : '' !!}>
                        @if ($cell && $cell['drawn'])
                            {{ $cell['value'] }}
                            @php
                                // The account holder is usually the company itself, already named in the letterhead.
                                $norm = fn ($x) => preg_replace('/[^a-z0-9]/', '', mb_strtolower((string) $x));
                                $holder = $norm($c['bank']['account_name']) === $norm($c['name']) ? null : $c['bank']['account_name'];
                            @endphp
                            <div class="t-meta" style="font-weight: normal;">{{ collect([$holder, $c['bank']['account_number'], $c['bank']['branch']])->filter()->implode(' · ') }}</div>
                        @else
                            {{ $cell['value'] ?? '' }}
                        @endif
                    </td>
                @endforeach
            </tr>
        @endforeach
    </table>
</div>

{{-- ── 4 · Supporting documents ── --}}
<div class="sec">
    <table class="bar"><tr><td class="num">4</td><td>{{ $t['attachments'] }}</td></tr></table>
    <table class="kv">
        <tr class="last">
            <td class="v" style="width: auto;">
                @forelse ($docs as $name)
                    <span class="nowrap"><span class="b" style="color: {{ $b['ink'] }};">{{ $loop->iteration }}.</span>&nbsp;{{ $name }}</span>@if (! $loop->last)<span style="color: #8a94a6;">&nbsp;&nbsp;&nbsp;</span> @endif
                @empty
                    <span class="faint">{{ $t['noneAttached'] }}</span>
                @endforelse
            </td>
        </tr>
    </table>
</div>

{{-- ── 5 · Authorisation ── --}}
<div class="sec" style="page-break-inside: avoid;">
    <table class="bar"><tr><td class="num">5</td><td>{{ $t['authorisation'] }}</td></tr></table>
    <table class="auth">
        @foreach ($doc['signatories'] as $s)
            @php $edge = $loop->last ? ' border-bottom: 0;' : ''; $pending = $s['state'] === 'pending'; @endphp
            <tr>
                <td class="nowrap" style="{{ $edge }} width: 25%;">
                    <span class="b nowrap" style="font-size: 10pt;">{{ $s['caption'] }}</span> <span class="t-meta">· {{ $s['role'] }}</span>
                </td>
                <td style="{{ $edge }} width: 28%;">
                    @if ($s['name'])
                        <span class="b" style="font-size: 10pt;">{{ $s['name'] }}</span>
                    @else
                        <span class="t-meta">—</span>
                    @endif
                </td>
                <td style="{{ $edge }} width: 19%;">
                    @if ($s['date'])
                        <span class="nowrap" style="font-size: 9.5pt;">{{ $s['date'] }}</span>
                    @else
                        <span class="t-meta">—</span>
                    @endif
                </td>
                <td style="{{ $edge }} padding-top: 2pt; padding-bottom: 2pt;">
                    <table><tr>
                        <td style="width: 50%; height: 20pt; vertical-align: middle; border: 0; padding: 0 6pt 0 0;">
                            @if ($s['signature'])
                                <img src="{{ $s['signature'] }}" alt="" style="max-height: 19pt; max-width: 72pt;">
                            @else
                                <div style="border-bottom: .8pt {{ $pending ? 'dashed #8a94a6' : 'solid #0b1220' }}; height: 16pt;"></div>
                            @endif
                        </td>
                        <td style="vertical-align: middle; border: 0; padding: 0;">
                            @if ($s['stamp'])
                                @include('vouchers.parts.stamp', ['kind' => $s['stamp']])
                            @elseif ($pending)
                                <span class="t-meta i">{{ $s['meta'] }}</span>
                            @endif
                        </td>
                    </tr></table>
                </td>
            </tr>
        @endforeach
    </table>
</div>

{{-- ── footer ── --}}
<table class="foot">
    <tr>
        <td style="padding-right: 12pt;">
            <div style="font-size: 9pt; line-height: 1.4;">@include('vouchers.parts.footer-verify')</div>
        </td>
        <td style="width: 1%; white-space: nowrap; text-align: right; padding-right: 7pt; vertical-align: top;">
            <div class="t-label">{{ $t['scanToVerify'] }}</div>
            <div class="t-meta" style="margin-top: 2pt;">{{ $t['status'] }}: <span class="b" style="color: {{ $b['ink'] }};">{{ $v['status_label'] }}</span></div>
            <div class="t-meta">{{ $t['generated'] }} {{ $doc['generated_at'] }}</div>
        </td>
        <td style="width: {{ $qrW }}pt; padding-top: 0;">@include('vouchers.parts.qr', ['cell' => $qrCell])</td>
    </tr>
</table>
@endsection
