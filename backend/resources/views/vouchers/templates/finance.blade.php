{{--
  03 · Finance Professional — a page from the books, money first.

  Section order:
    1. Compact header — company name and contact lines left, logo right.
    2. Solid secondary-colour title bar — document title, bank/cash kind,
       voucher number in tabular figures.
    3. FINANCIAL SUMMARY box — the most prominent part of the page: total
       payable set very large with its currency and the amount in words,
       beside a boxed grid of payment method, bank, account name, account no.,
       branch and reference (cash float / received by on a cash voucher).
    4. Full payment details table — every particulars row (incl. paid on,
       payment ref., paid so far, balance, cheque) and the drawn-on account.
    5. Particulars ledger — # | Reference | Description | Currency | Amount,
       closed by a double-underlined total row.
    6. Request line-fields — payee, date, requested by, department, category.
    7. Supporting documents and remarks side by side.
    8. Sign-off table — Role | Name | Signature | Date | Status/stamp;
       pending rows read "Awaiting …".
    9. Footer — footer text, verification code, status, generated time, QR.
  Figures are set in DejaVu Sans Mono.
--}}
@extends('vouchers.layout')

@php
    $b = $doc['brand']; $t = $doc['t']; $v = $doc['voucher']; $c = $doc['company']; $p = $doc['payment'];
    $grid = '#b9c2cf'; $muted = '#4f5a6b'; $head = '#eef1f5';
    $mono = '"DejaVu Sans Mono", monospace';
    $isBank = $v['kind'] === 'bank';
    $dash = fn ($x) => filled($x) ? $x : '—';

    // DomPDF sets every line box 1.28× taller than asked (DejaVu's height ×
    // dompdf's font_height_ratio of 1.1), so the PDF gets line-heights divided
    // by that factor: both renderers then show the same, readable ~1.35 leading.
    $lh = fn (float $x) => $doc['mode'] === 'pdf' ? round($x / 1.28, 3) : $x;

    // The summary grid: the six fields a payments clerk needs to move the money.
    $summary = $isBank
        ? [
            [$t['paymentMethod'], $p['method']], [$t['payeeBank'], $p['bank']],
            [$t['accountName'], $p['account_name']], [$t['accountNo'], $p['account_no']],
            [$t['branch'], $p['branch']], [$t['reference'], $p['reference']],
        ]
        : [
            [$t['paymentMethod'], $p['method']], [$t['reference'], $p['reference']],
            [$t['cashFloat'], $p['cash_float']], [$t['receivedBy'], $p['received_by']],
            [$t['voucherType'], $p['type']], [$t['currency'], $p['currency']],
        ];
    $summaryRows = array_chunk($summary, 2);

    // Payment details: every particulars row as a four-across register, the
    // drawn-on account filling the last line.
    $cells = array_map(fn ($row) => [$row[0], e($row[1]), 1, $row[0] === $t['amount'] ? 'b f-mono' : ''], $doc['particulars']);
    $drawn = null;
    if ($isBank && $c['bank']) {
        $drawn = [e($c['bank']['name']), e($c['bank']['account_name']),
            e(collect([$c['bank']['account_number'], $c['bank']['branch']])->filter()->implode(' · '))];
    }
    $cols = 5;
    $detailRows = [];
    $line = []; $used = 0;
    foreach ($cells as $cell) {
        $line[] = $cell; $used++;
        if ($used >= $cols) { $detailRows[] = $line; $line = []; $used = 0; }
    }
    if ($drawn) {
        // The drawn-on account takes the rest of the last line, or a line of its own.
        if ($cols - $used < 2 && $line) { $line[] = ['', '&nbsp;', $cols - $used, '']; $detailRows[] = $line; $line = []; $used = 0; }
        $line[] = [$t['drawnOn'], '<span class="b">'.$drawn[0].'</span> · '.$drawn[1].' · '.$drawn[2], $cols - $used, ''];
        $detailRows[] = $line; $line = []; $used = 0;
    }
    if ($line) { $line[] = ['', '&nbsp;', $cols - $used, '']; $detailRows[] = $line; }

    $sigs = $doc['signatories'];
    $dense = count($sigs) > 4;
@endphp

@section('page_margin', '8mm 12mm 7mm')

@section('styles')
    body { line-height: {{ $lh(1.32) }}; }
    .f-mono { font-family: {!! $mono !!}; }
    .f-lab { font-size: 7.5pt; font-weight: bold; letter-spacing: .08em; text-transform: uppercase; color: {{ $muted }}; }
    .f-sec { font-size: 11pt; font-weight: bold; letter-spacing: .06em; text-transform: uppercase; color: {{ $b['ink'] }};
             padding-bottom: 3pt; border-bottom: 1.6pt solid {{ $b['primary'] }}; }

    .f-title td { background: {{ $b['secondary'] }}; color: {{ $b['on_secondary'] }}; padding: 5pt 10pt; vertical-align: middle; }

    .f-sum { border: 1.6pt solid #0b1220; }
    .f-sum-total { background: {{ $b['tint'] }}; border-right: 1pt solid #0b1220; padding: 8pt 12pt; vertical-align: middle; }
    .f-sgrid td { border-bottom: .8pt solid {{ $grid }}; border-left: .8pt solid {{ $grid }}; padding: 4pt 9pt; vertical-align: top; }
    .f-sgrid tr.last td { border-bottom: 0; }

    .f-kv { table-layout: fixed; }
    .f-kv td { border: .7pt solid {{ $grid }}; padding: 4pt 7pt; vertical-align: top; }
    .f-kv .fv { font-size: 9.5pt; margin-top: 1pt; }

    .f-led th { border-top: 1.4pt solid #0b1220; border-bottom: 1pt solid #0b1220; padding: 5pt 6pt; background: {{ $head }}; }
    .f-led td { padding: 4pt 6pt; border-bottom: .7pt solid {{ $grid }}; vertical-align: top; }
    .f-led td.col, .f-led th.col { border-left: .7pt solid {{ $grid }}; }
    .f-led tr.total td { border-bottom: 0; padding-top: 5pt; vertical-align: middle; }

    .f-field td { padding: 6pt 10pt 0 0; vertical-align: top; }
    .f-field .fv { border-bottom: .8pt solid #0b1220; padding-bottom: 2pt; font-size: 10.5pt; font-weight: bold; }

    .f-box { border: .8pt solid {{ $grid }}; padding: 5pt 8pt; vertical-align: top; }

    .f-appr { page-break-inside: avoid; }
    .f-appr tr { page-break-inside: avoid; }
    .f-appr th { background: {{ $head }}; border: .7pt solid {{ $grid }}; padding: 4pt 7pt; }
    .f-appr td { border: .7pt solid {{ $grid }}; padding: 4pt 7pt; vertical-align: middle; height: {{ $dense ? 16 : 18 }}pt; }

    .f-foot { font-size: 8.5pt; color: {{ $muted }}; line-height: {{ $lh(1.45) }}; vertical-align: middle; }
@endsection

@section('content')
{{-- 1 · compact header --}}
<table>
    <tr>
        <td style="vertical-align: middle;">
            <div style="font-size: 14pt; font-weight: bold; line-height: {{ $lh(1.3) }};">{{ $c['name'] }}</div>
            @if ($c['lines'])<div class="t-meta" style="margin-top: 1pt; color: {{ $muted }};">{{ $c['lines'][0] }}@if (count($c['lines']) > 1)<br>{{ implode(' · ', array_slice($c['lines'], 1)) }}@endif</div>@endif
            @if ($c['header_text'])<div class="t-meta" style="margin-top: 1pt; color: #0b1220;">{{ $c['header_text'] }}</div>@endif
        </td>
        <td style="width: {{ $c['logo'] ? 110 : 48 }}pt; text-align: right; vertical-align: middle;">@include('vouchers.parts.logo', ['height' => 44, 'width' => 110])</td>
    </tr>
</table>

{{-- 2 · title bar --}}
<table class="f-title" style="margin-top: 7pt; table-layout: fixed;">
    <tr>
        <td class="nowrap" style="width: 42%; font-size: 13pt; font-weight: bold; letter-spacing: .06em; text-transform: uppercase;">{{ $v['type_label'] }}</td>
        <td class="nowrap" style="width: 20%; text-align: center; font-size: 9pt; font-weight: bold; letter-spacing: .1em; text-transform: uppercase;">{{ $v['kind_label'] }}</td>
        <td class="r nowrap" style="width: 38%;">
            <span style="font-size: 8pt; letter-spacing: .08em; text-transform: uppercase;">{{ $t['voucherNo'] }}</span>&nbsp;
            <span class="f-mono b" style="font-size: 13pt;">{{ $v['number'] }}</span>
        </td>
    </tr>
</table>

{{-- 3 · financial summary --}}
<table class="f-sum" style="margin-top: 7pt;">
    <tr>
        <td class="f-sum-total" style="width: 50%;">
            <div class="f-lab" style="color: {{ $b['ink'] }};">{{ $t['totalPayable'] }}</div>
            <div style="margin-top: 4pt; line-height: {{ $lh(1.3) }};">
                <span class="f-mono b" style="font-size: 12pt; color: {{ $b['ink'] }};">{{ $v['currency'] }}</span>
                <span class="f-mono b" style="font-size: 26pt; letter-spacing: -.5pt;">{{ $v['amount'] }}</span>
            </div>
            <div class="f-lab" style="margin-top: 5pt;">{{ $t['amountWords'] }}</div>
            <div class="i" style="font-size: 10pt; line-height: {{ $lh(1.35) }}; margin-top: 1pt;">{{ $v['amount_words'] }}</div>
        </td>
        <td style="width: 50%; padding: 0;">
            <table class="f-sgrid">
                @foreach ($summaryRows as $pair)
                    <tr class="{{ $loop->last ? 'last' : '' }}">
                        @foreach ($pair as [$term, $value])
                            <td style="width: 50%;">
                                <div class="f-lab">{{ $term }}</div>
                                <div class="b" style="font-size: 10.5pt; margin-top: 1pt;">{{ $dash($value) }}</div>
                            </td>
                        @endforeach
                    </tr>
                @endforeach
            </table>
        </td>
    </tr>
</table>

{{-- 4 · full payment details --}}
<div class="f-sec" style="margin-top: 8pt;">{{ $t['paymentDetails'] }}</div>
<table class="f-kv" style="margin-top: 4pt;">
    @foreach ($detailRows as $row)
        <tr>
            @foreach ($row as $cell)
                <td style="width: 20%;" @if (! empty($cell[2])) colspan="{{ $cell[2] }}" @endif>
                    <div class="f-lab">{{ $cell[0] }}</div>
                    <div class="fv {{ $cell[3] ?? '' }}">{!! $cell[1] !!}</div>
                </td>
            @endforeach
        </tr>
    @endforeach
</table>

{{-- 5 · particulars ledger --}}
<table class="f-led" style="margin-top: 8pt;">
    <thead>
        <tr>
            <th class="f-lab c" style="width: 4%;">#</th>
            <th class="f-lab col" style="width: 17%;">{{ $t['reference'] }}</th>
            <th class="f-lab col" style="color: {{ $b['ink'] }};">{{ $t['particulars'] }} · {{ $t['description'] }}</th>
            <th class="f-lab col c" style="width: 8%;">{{ $t['currency'] }}</th>
            <th class="f-lab col r" style="width: 14%;">{{ $t['amount'] }}</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td class="f-mono c">1</td>
            <td class="f-mono col" style="font-size: 9.5pt;">{{ $dash($v['reference']) }}</td>
            <td class="col">
                <div class="b" style="font-size: 10.5pt;">{{ $dash($v['purpose']) }}</div>
                @if ($v['description'])<div style="margin-top: 2pt; line-height: {{ $lh(1.4) }};">{{ $v['description'] }}</div>@endif
            </td>
            <td class="f-mono col c">{{ $v['currency'] }}</td>
            <td class="f-mono col r" style="font-size: 10.5pt;">{{ $v['amount'] }}</td>
        </tr>
        <tr class="total">
            <td colspan="3" class="r f-lab" style="font-size: 8.5pt; color: #0b1220;">{{ $t['totalPayable'] }}</td>
            <td class="f-mono c b col">{{ $v['currency'] }}</td>
            <td class="f-mono r b col" style="font-size: 12pt; background: {{ $b['tint'] }};">
                <div style="border-bottom: 3pt double #0b1220; padding-bottom: 2pt;">{{ $v['amount'] }}</div>
            </td>
        </tr>
    </tbody>
</table>

{{-- 6 · request line-fields --}}
<table class="f-field" style="margin-top: 2pt;">
    <tr>
        <td style="width: 34%;">
            <div class="f-lab">{{ $t['payee'] }}</div>
            <div class="fv">{{ $v['payee'] }}</div>
        </td>
        <td style="width: 20%;">
            <div class="f-lab">{{ $t['requestedBy'] }}</div>
            <div class="fv">{{ $v['requester'] }}</div>
            @if ($v['requester_title'])<div class="t-meta" style="color: {{ $muted }};">{{ $v['requester_title'] }}</div>@endif
        </td>
        <td style="width: 18%;">
            <div class="f-lab">{{ $t['department'] }}</div>
            <div class="fv">{{ $v['department'] }}</div>
            @if ($v['cost_centre'])<div class="t-meta f-mono" style="color: {{ $muted }};">{{ $v['cost_centre'] }}</div>@endif
        </td>
        <td style="width: 14%;">
            <div class="f-lab">{{ $t['category'] }}</div>
            <div class="fv">{{ $v['category'] }}</div>
        </td>
        <td style="padding-right: 0;">
            <div class="f-lab">{{ $t['date'] }}</div>
            <div class="fv f-mono nowrap">{{ $v['date'] }}</div>
        </td>
    </tr>
</table>

{{-- 7 · documents + remarks --}}
<table style="margin-top: 8pt;">
    <tr>
        <td class="f-box" style="width: 50%;">
            <div class="f-lab">{{ $t['attachments'] }} ({{ count($doc['attachments']) }})</div>
            @include('vouchers.parts.attachments', ['itemStyle' => 'display: inline; margin-right: 10pt; font-size: 9.5pt; margin-top: 1pt; line-height: '.$lh(1.35).';'])
        </td>
        <td style="width: 8pt;"></td>
        <td class="f-box">
            <div class="f-lab">{{ $t['remarks'] }}</div>
            <div style="font-size: 9.5pt; line-height: {{ $lh(1.4) }}; margin-top: 2pt;">{{ $v['remarks'] ?: '—' }}</div>
        </td>
    </tr>
</table>

{{-- 8 · sign-off table --}}
<div style="page-break-inside: avoid;">
<div class="f-sec" style="margin-top: 7pt;">{{ $t['authorisation'] }}</div>
<table class="f-appr" style="margin-top: 4pt;">
    <thead>
        <tr>
            <th class="f-lab" style="width: 26%;">{{ $t['role'] }}</th>
            <th class="f-lab" style="width: 26%;">{{ $t['name'] }}</th>
            <th class="f-lab c" style="width: 15%;">{{ $t['signature'] }}</th>
            <th class="f-lab" style="width: 18%;">{{ $t['date'] }}</th>
            <th class="f-lab c" style="width: 15%;">{{ $t['status'] }}</th>
        </tr>
    </thead>
    <tbody>
        @foreach ($sigs as $s)
            @php $pending = $s['state'] === 'pending'; @endphp
            <tr>
                <td class="nowrap">
                    <span class="b" style="font-size: 10pt;">{{ $s['caption'] }}</span>
                    <span class="t-meta" style="color: {{ $muted }};">· {{ $s['role'] }}</span>
                </td>
                <td>
                    @if ($s['name'])
                        <div class="nowrap" style="font-size: 10pt; font-weight: bold;">{{ $s['name'] }}</div>
                        @if (! $s['date'] && $s['meta'])<div class="t-meta" style="color: {{ $muted }};">{{ $s['meta'] }}</div>@endif
                    @else
                        <div class="i" style="font-size: 9pt; color: {{ $muted }};">{{ $s['meta'] }}</div>
                    @endif
                </td>
                <td class="c">
                    @if ($s['signature'])
                        <img src="{{ $s['signature'] }}" alt="" style="max-height: {{ $dense ? 16 : 18 }}pt; max-width: 96pt;">
                    @elseif ($pending)
                        <div style="border-bottom: .8pt dotted #6b7689; height: 14pt; margin: 0 6pt;"></div>
                    @endif
                </td>
                <td class="nowrap" style="font-size: 9pt;">{{ $s['date'] ?: '—' }}</td>
                <td class="c">
                    @if ($s['stamp'])
                        @include('vouchers.parts.stamp', ['kind' => $s['stamp']])
                    @elseif ($pending)
                        <span class="up" style="font-size: 8pt; letter-spacing: .08em; color: {{ $muted }};">{{ $t['pending'] }}</span>
                    @else
                        <span class="b" style="font-size: 9pt; color: #0f7a54;">✓</span>
                    @endif
                </td>
            </tr>
        @endforeach
    </tbody>
</table>
</div>

{{-- 9 · footer --}}
<table style="margin-top: 7pt; border-top: 1.6pt solid #0b1220; page-break-inside: avoid;">
    <tr>
        <td class="f-foot" style="padding-top: 4pt; padding-right: 10pt;">
            @include('vouchers.parts.footer-verify')
            <br>{{ $t['status'] }}: <span class="b" style="color: #0b1220;">{{ $v['status_label'] }}</span> · {{ $t['original'] }} · {{ $t['generated'] }} {{ $doc['generated_at'] }}
        </td>
        <td class="f-foot r" style="width: 86pt; padding-top: 4pt; padding-right: 6pt;">
            <span class="b" style="color: #0b1220;">{{ $t['scanToVerify'] }}</span><br>
            <span class="f-mono">{{ $v['verification_code'] }}</span>
        </td>
        <td style="width: 62pt; padding-top: 1pt; text-align: right;">@include('vouchers.parts.qr', ['cell' => 1.8])</td>
    </tr>
</table>
@endsection
