{{--
  08 · Formal Document — the official bordered form, for printing and records.

  Serif throughout, every field in its own labelled bordered cell, the whole
  form held inside one heavy outer rule. The brand colour appears only in the
  title box and the signature captions.

  Section order:
    1. Heavy outer border around the whole form.
    2. Letterhead: logo left; company name in capitals centred with its
       address/contact lines; boxed "Voucher no. / Date" right.
    3. Centred double-ruled title box (type_label), flanked by the kind (left)
       and "Original" (right).
    4. Voucher metadata grid: requested by, department, cost centre, category,
       voucher type, reference, payee — each in a labelled bordered cell.
    5. Purpose / description cell.
    6. Amount cell (large) beside the amount-in-words cell.
    7. "Payment particulars" band + grid, two pairs per row. Every particulars
       row prints once: amount in the total cell (6), paid on / payment ref. in
       the finance office panel (10), all others here.
    8. Supporting documents cell + remarks cell.
    9. Formal signature section: bordered boxes, caption strip, dotted
       Signature / Name / Date lines, stamp (pending: empty lines, "Awaiting …"
       on the date line). Never splits across pages.
   10. "For finance office use only" boxed panel: drawn on, payment ref.,
       paid on, verification code + QR.
   11. Ruled footer: footer text, status, generated time.
--}}
@extends('vouchers.layout')

@section('font', 'serif')
@section('page_margin', '6mm 10mm 6mm')

@php
    $b = $doc['brand']; $t = $doc['t']; $v = $doc['voucher']; $c = $doc['company']; $p = $doc['payment'];
    $ink = '#0b1220'; $grid = '#3b4452'; $muted = '#4a5466'; $wash = '#f1f2f4';
    $sansFont = '"DejaVu Sans", Helvetica, Arial, sans-serif';

    // Every particulars row prints once: the amount lives in the total cell,
    // paid on / payment ref. in the finance office panel, the rest in the grid.
    $shownElsewhere = [$t['amount'], $t['paidOn'], $t['paymentRef']];
    $pairs = array_chunk(array_values(array_filter($doc['particulars'], fn ($row) => ! in_array($row[0], $shownElsewhere, true))), 2);

    // Signature boxes: one row up to four, otherwise rows of three.
    $sigs = $doc['signatories'];
    $perRow = count($sigs) <= 4 ? max(2, count($sigs)) : 3;
    $sigRows = array_chunk($sigs, $perRow);
    $hasBank = $v['kind'] === 'bank' && $c['bank'];
    $qrW = $doc['qr'] ? round($doc['qr']['size'] * 1.8 + 8) : 0;
@endphp

@section('styles')
    .frame { border: 2.6pt solid {{ $ink }}; padding: 2pt; }
    .inner { border: .8pt solid {{ $ink }}; }
    .f { font-family: {!! $sansFont !!}; font-size: 7.5pt; line-height: 1.3; letter-spacing: .06em; text-transform: uppercase; color: {{ $muted }}; font-weight: bold; }
    .grid { table-layout: fixed; }
    .grid td { border: .7pt solid {{ $grid }}; padding: 4pt 6pt 4pt; vertical-align: top; line-height: 1.3; }
    .val { font-size: 10pt; margin-top: 1.5pt; }
    .sub { font-size: 8.5pt; color: {{ $muted }}; }
    .band { background: {{ $wash }}; border-top: .7pt solid {{ $grid }}; padding: 3pt 6pt; text-align: center; line-height: 1.3; }
    .band span { font-family: {!! $sansFont !!}; font-size: 8.5pt; font-weight: bold; letter-spacing: .2em; text-transform: uppercase; color: {{ $ink }}; }
    .title-box { border: 2.4pt double {{ $b['ink'] }}; padding: 2pt 22pt 1pt; display: inline-block; }
    .title { font-size: 14pt; font-weight: bold; letter-spacing: .15em; text-transform: uppercase; color: {{ $b['ink'] }}; line-height: 1.3; }
    .no-box td { border: .8pt solid {{ $ink }}; padding: 4pt 6pt; line-height: 1.3; }
    .sig { table-layout: fixed; page-break-inside: avoid; }
    .sig td.box { border: .7pt solid {{ $grid }}; padding: 0; vertical-align: top; }
    .sig .cap { background: {{ $wash }}; border-bottom: .7pt solid {{ $grid }}; padding: 4pt 6pt; line-height: 1.3; }
    .line td { padding: 4pt 5pt 0; line-height: 1.3; }
    .line td.k { width: 23pt; font-family: {!! $sansFont !!}; font-size: 7.5pt; letter-spacing: 0; text-transform: uppercase; color: {{ $muted }}; font-weight: bold; vertical-align: bottom; padding-right: 3pt; padding-bottom: 2pt; }
    .line td.v { border-bottom: .8pt dotted {{ $ink }}; vertical-align: bottom; padding-left: 0; padding-bottom: 2pt; font-size: 9.5pt; }
    .office { border: 1.5pt solid {{ $ink }}; }
    .office td.o { border-left: .7pt solid {{ $grid }}; padding: 4pt 6pt; vertical-align: top; line-height: 1.3; }
    .foot { font-size: 8.5pt; color: {{ $muted }}; line-height: 1.35; }
@endsection

@section('content')
<div class="frame"><div class="inner">

    {{-- Letterhead: logo left, company centred, number box right --}}
    <table>
        <tr>
            <td style="width: 74pt; padding: 7pt 4pt 7pt 8pt; vertical-align: middle;">@include('vouchers.parts.logo', ['height' => 46, 'width' => 62])</td>
            <td class="c" style="padding: 7pt 4pt; vertical-align: middle;">
                <div style="font-size: 12.5pt; font-weight: bold; letter-spacing: .02em; text-transform: uppercase; line-height: 1.25;">{{ $c['name'] }}</div>
                <div class="t-meta" style="line-height: 1.35; margin-top: 3pt; color: {{ $muted }};">@include('vouchers.parts.company-lines')</div>
                @if ($c['header_text'])<div class="i t-meta" style="margin-top: 2pt; color: {{ $ink }};">{{ $c['header_text'] }}</div>@endif
            </td>
            <td style="width: 140pt; padding: 7pt 8pt 7pt 4pt; vertical-align: middle;">
                <table class="no-box">
                    <tr><td style="width: 40pt; background: {{ $wash }}; vertical-align: middle;"><div class="f">{{ $t['voucherNo'] }}</div></td><td class="b nowrap" style="font-size: 12pt; vertical-align: middle;">{{ $v['number'] }}</td></tr>
                    <tr><td style="background: {{ $wash }}; vertical-align: middle;"><div class="f">{{ $t['date'] }}</div></td><td style="font-size: 10.5pt; vertical-align: middle;">{{ $v['date'] }}</td></tr>
                </table>
            </td>
        </tr>
    </table>

    {{-- Boxed title --}}
    <table style="border-top: .7pt solid {{ $grid }};">
        <tr>
            <td class="sans up nowrap" style="width: 19%; padding: 6pt 8pt; vertical-align: middle; font-size: 8.5pt; font-weight: bold; letter-spacing: .1em; color: {{ $ink }};">{{ $v['kind_label'] }}</td>
            <td class="c" style="padding: 6pt 0 5pt; vertical-align: middle;"><div class="title-box"><div class="title nowrap">{{ $v['type_label'] }}</div></div></td>
            <td class="sans up r nowrap" style="width: 25%; padding: 6pt 8pt; vertical-align: middle; font-size: 8.5pt; letter-spacing: .08em; color: {{ $muted }};">{{ $t['original'] }}</td>
        </tr>
    </table>

    {{-- Voucher metadata grid --}}
    <table class="grid">
        <tr>
            <td style="width: 28%;"><div class="f">{{ $t['requestedBy'] }}</div><div class="val b">{{ $v['requester'] }}</div>@if ($v['requester_title'])<div class="sub">{{ $v['requester_title'] }}</div>@endif</td>
            <td style="width: 26%;"><div class="f">{{ $t['department'] }}</div><div class="val">{{ $v['department'] }}</div></td>
            <td style="width: 20%;"><div class="f">{{ $t['costCentre'] }}</div><div class="val">{{ $v['cost_centre'] ?: '—' }}</div></td>
            <td style="width: 26%;"><div class="f">{{ $t['category'] }}</div><div class="val">{{ $v['category'] }}</div></td>
        </tr>
        <tr>
            <td><div class="f">{{ $t['voucherType'] }}</div><div class="val">{{ $p['type'] ?: $v['type_label'] }}</div></td>
            <td><div class="f">{{ $t['reference'] }}</div><div class="val">{{ $v['reference'] ?: '—' }}</div></td>
            <td colspan="2"><div class="f">{{ $t['payee'] }} / {{ $t['beneficiary'] }}</div><div class="val b" style="font-size: 11pt;">{{ $v['payee'] }}</div></td>
        </tr>
        <tr>
            <td colspan="4">
                <div class="f">{{ $t['purpose'] }} &amp; {{ $t['description'] }}</div>
                <div class="val b">{{ $v['purpose'] ?: '—' }}</div>
                @if ($v['description'])<div style="font-size: 9.5pt; line-height: 1.35; margin-top: 2pt;">{{ $v['description'] }}</div>@endif
            </td>
        </tr>
        <tr>
            <td style="background: {{ $wash }}; vertical-align: middle;">
                <div class="f">{{ $t['totalPayable'] }} ({{ $v['currency'] }})</div>
                <div class="b r nowrap" style="font-size: 19pt; line-height: 1.2; margin-top: 1pt;">{{ $v['amount'] }}</div>
            </td>
            <td colspan="3" style="vertical-align: middle;">
                <div class="f">{{ $t['amountWords'] }}</div>
                <div class="i" style="font-size: 11pt; line-height: 1.35; margin-top: 2pt;">{{ $v['amount_words'] }}</div>
            </td>
        </tr>
    </table>

    {{-- Payment particulars: two pairs per row --}}
    <div class="band"><span>{{ $t['paymentParticulars'] }}</span></div>
    <table class="grid">
        @foreach ($pairs as $pair)
            <tr>
                @foreach ($pair as [$term, $value])
                    <td style="width: 19%; background: {{ $wash }}; vertical-align: middle;"><div class="f">{{ $term }}</div></td>
                    <td style="width: 31%; font-size: 9.5pt; vertical-align: middle;">{{ $value }}</td>
                @endforeach
                @if (count($pair) === 1)<td style="width: 19%; background: {{ $wash }};"></td><td style="width: 31%;"></td>@endif
            </tr>
        @endforeach
        <tr>
            <td colspan="2"><div class="f">{{ $t['attachments'] }}</div>@include('vouchers.parts.attachments', ['itemStyle' => 'font-size: 9.5pt; margin-top: 1.5pt; line-height: 1.3;'])</td>
            <td colspan="2"><div class="f">{{ $t['remarks'] }}</div><div style="font-size: 9.5pt; line-height: 1.35; margin-top: 1.5pt;">{{ $v['remarks'] ?: '—' }}</div></td>
        </tr>
    </table>

    {{-- Signatures in ruled boxes --}}
    <div style="page-break-inside: avoid;">
        @foreach ($sigRows as $row)
            <table class="sig">
                <tr>
                    @foreach ($row as $s)
                        <td class="box" style="width: {{ round(100 / $perRow, 2) }}%;">
                            <div class="cap">
                                <span class="f" style="color: {{ $b['ink'] }};">{{ $s['caption'] }}</span><span class="sub"> · {{ $s['role'] }}</span>
                            </div>
                            <table class="line">
                                <tr><td colspan="2" style="padding-top: 3pt;">
                                    <table><tr>
                                        <td class="f" style="padding: 0 3pt 2pt 0; vertical-align: bottom; width: 1%;">{{ $t['signature'] }}</td>
                                        <td style="padding: 0; border-bottom: .8pt dotted {{ $ink }}; vertical-align: bottom;">@include('vouchers.parts.signature-mark', ['height' => 32, 'align' => 'center'])</td>
                                    </tr></table>
                                </td></tr>
                                <tr><td class="k">{{ $t['name'] }}</td><td class="v" style="font-size: 9.5pt; color: {{ $ink }};">{!! $s['name'] ? e($s['name']) : '&nbsp;' !!}</td></tr>
                                <tr><td class="k">{{ $t['date'] }}</td><td class="v {{ $s['state'] === 'pending' ? 'i' : '' }}" style="font-size: 8.5pt; {{ $s['state'] === 'pending' ? 'color: '.$muted.';' : '' }}">{{ $s['date'] ?: $s['meta'] }}</td></tr>
                            </table>
                            <div style="height: 2pt;"></div>
                        </td>
                    @endforeach
                    @for ($i = count($row); $i < $perRow; $i++)
                        <td class="box" style="width: {{ round(100 / $perRow, 2) }}%; background: {{ $wash }};"></td>
                    @endfor
                </tr>
            </table>
        @endforeach
    </div>

    {{-- For finance office use only --}}
    <div style="padding: 5pt 6pt; page-break-inside: avoid;">
        <div class="office">
            <div class="c" style="background: {{ $ink }}; padding: 3pt; line-height: 1.3;">
                <span class="sans" style="font-size: 8.5pt; font-weight: bold; letter-spacing: .2em; text-transform: uppercase; color: #fff;">{{ $t['financeUse'] }}</span>
            </div>
            <table style="table-layout: fixed;">
                <tr>
                    <td class="o" style="border-left: 0; width: 26%;">
                        @if ($hasBank)
                            @include('vouchers.parts.bank', ['labelStyle' => 'font-family: '.$sansFont.'; font-size: 7.5pt; font-weight: bold; letter-spacing: .06em; text-transform: uppercase; color: '.$muted.';'])
                        @else
                            <div class="f">{{ $t['drawnOn'] }}</div>
                            <div style="font-size: 10pt; margin-top: 1pt;">{{ $v['payment_method'] }}</div>
                        @endif
                    </td>
                    <td class="o" style="width: 19%;"><div class="f">{{ $t['paymentRef'] }}</div><div style="font-size: 10pt; margin-top: 2pt;">{{ $p['payment_ref'] ?: '—' }}</div></td>
                    <td class="o" style="width: 15%;"><div class="f">{{ $t['paidOn'] }}</div><div class="nowrap" style="font-size: 10pt; margin-top: 2pt;">{{ $p['paid_on'] ?: '—' }}</div></td>
                    <td class="o" style="padding-right: 3pt;">
                        <table><tr>
                            <td style="vertical-align: middle; padding: 0;">
                                <div class="f">{{ $t['verificationCode'] }}</div>
                                <div class="b nowrap" style="font-size: 10.5pt; margin-top: 2pt; letter-spacing: .02em;">{{ $v['verification_code'] ?: '—' }}</div>
                                <div class="t-meta" style="margin-top: 2pt;">{{ $t['scanToVerify'] }}</div>
                            </td>
                            <td style="vertical-align: middle; padding: 0; width: {{ $qrW }}pt;">@include('vouchers.parts.qr', ['cell' => 1.8])</td>
                        </tr></table>
                    </td>
                </tr>
            </table>
        </div>
    </div>

    {{-- Ruled footer --}}
    <table style="border-top: .8pt solid {{ $grid }}; page-break-inside: avoid;">
        <tr>
            <td class="foot" style="padding: 4pt 8pt;">{{ $c['footer_text'] }}</td>
            <td class="foot r nowrap" style="padding: 4pt 8pt; width: 250pt;">{{ $t['status'] }}: <span class="b" style="color: {{ $ink }};">{{ $v['status_label'] }}</span> · {{ $t['generated'] }} {{ $doc['generated_at'] }}</td>
        </tr>
    </table>

</div></div>
@endsection
