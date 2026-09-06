{{-- A4 portrait voucher. DomPDF has no flexbox or grid, so the layout is built
     from tables — the same broadsheet proportions, expressed in table cells. --}}
<!DOCTYPE html>
<html lang="{{ $locale }}">
<head>
<meta charset="utf-8">
<title>{{ $voucher->number }}</title>
<style>
  @font-face { font-family: 'poppins'; font-weight: 400; font-style: normal; src: url("{{ $fontPath }}/Poppins-Regular.ttf") format('truetype'); }
  @font-face { font-family: 'poppins'; font-weight: 500; font-style: normal; src: url("{{ $fontPath }}/Poppins-Medium.ttf") format('truetype'); }
  @font-face { font-family: 'poppins'; font-weight: 600; font-style: normal; src: url("{{ $fontPath }}/Poppins-SemiBold.ttf") format('truetype'); }
  @font-face { font-family: 'poppins'; font-weight: 700; font-style: normal; src: url("{{ $fontPath }}/Poppins-Bold.ttf") format('truetype'); }
  @font-face { font-family: 'poppins'; font-weight: 400; font-style: italic; src: url("{{ $fontPath }}/Poppins-Italic.ttf") format('truetype'); }

  @page { margin: 14mm 13mm 16mm; }
  * { box-sizing: border-box; }
  body { font-family: 'poppins', sans-serif; font-size: 9.5pt; line-height: 1.45; color: #201e1d; margin: 0; }

  .rule-heavy { border-bottom: 2.4pt solid #201e1d; }
  .rule-light { border-bottom: 0.5pt solid #d7d3d3; }
  .kicker { font-size: 6.6pt; letter-spacing: .09em; text-transform: uppercase; color: #605d5d; }
  .tnum { font-variant-numeric: tabular-nums; }
  .muted { color: #605d5d; }

  table { width: 100%; border-collapse: collapse; }
  td { vertical-align: top; }

  .brand-name { font-size: 14pt; font-weight: 700; letter-spacing: -.01em; }
  .doc-type { font-size: 7.4pt; letter-spacing: .12em; text-transform: uppercase; color: #605d5d; }
  .doc-number { font-size: 12pt; font-weight: 600; }

  .meta td { padding: 5pt 10pt 5pt 0; }
  .meta .label { font-size: 6.6pt; letter-spacing: .08em; text-transform: uppercase; color: #605d5d; }
  .meta .value { font-size: 9.5pt; }

  .purpose-title { font-size: 12pt; font-weight: 600; margin: 3pt 0 4pt; }
  .amount-figure { font-size: 17pt; font-weight: 600; text-align: right; white-space: nowrap; }
  .amount-words { font-style: italic; }

  .sig-cell { width: 33.33%; padding: 0 7pt 0 0; }
  .sig-box { height: 46pt; border-bottom: 0.7pt solid #9b9797; text-align: left; }
  .sig-box img { max-height: 42pt; max-width: 100%; }
  .sig-label { font-size: 6.6pt; letter-spacing: .07em; text-transform: uppercase; color: #605d5d; padding-top: 3pt; }
  .sig-name { font-size: 9pt; font-weight: 600; }
  .sig-meta { font-size: 7.4pt; color: #605d5d; }

  .stamp { border: 1.4pt solid #d6006c; color: #d6006c; font-size: 8pt; font-weight: 600;
           letter-spacing: .1em; text-transform: uppercase; padding: 3pt 9pt; display: inline-block; }
  .stamp-ok { border-color: #0088b0; color: #0088b0; }

  .foot { position: fixed; bottom: -9mm; left: 0; right: 0; font-size: 7pt; color: #605d5d; }
  .attach td { padding: 3pt 0; font-size: 8.4pt; }
</style>
</head>
<body>

{{-- ─────────────────────────────── masthead ─────────────────────────────── --}}
<table class="rule-heavy" style="padding-bottom: 8pt;">
  <tr>
    <td style="width: 62%;">
      @if ($logo)
        <img src="{{ $logo }}" style="max-height: 40pt; max-width: 150pt; margin-bottom: 4pt;" alt="">
      @endif
      <div class="brand-name">{{ $company->name }}</div>
      <div class="muted" style="font-size: 7.8pt;">
        {{ collect([$company->address, $company->phone, $company->email])->filter()->implode(' · ') }}
      </div>
    </td>
    <td style="width: 38%; text-align: right;">
      <div class="doc-type">{{ $typeLabel }}</div>
      <div class="doc-number tnum">{{ $voucher->number }}</div>
      <div style="margin-top: 5pt;">
        @if ($voucher->status === 'approved')
          <span class="stamp stamp-ok">{{ $t['approved'] }}</span>
        @elseif ($voucher->status === 'rejected')
          <span class="stamp">{{ $t['rejected'] }}</span>
        @else
          <span class="stamp" style="border-color:#7d7979;color:#7d7979;">{{ $statusLabel }}</span>
        @endif
      </div>
    </td>
  </tr>
</table>

{{-- ──────────────────────────────── details ─────────────────────────────── --}}
<table class="meta rule-light" style="margin-top: 9pt;">
  <tr>
    <td style="width: 25%;"><div class="label">{{ $t['date'] }}</div><div class="value">{{ $voucher->voucher_date?->format('j F Y') }}</div></td>
    <td style="width: 25%;"><div class="label">{{ $t['department'] }}</div><div class="value">{{ $voucher->department?->name ?? '—' }}</div></td>
    <td style="width: 25%;"><div class="label">{{ $t['payee'] }}</div><div class="value">{{ $voucher->payee }}</div></td>
    <td style="width: 25%;"><div class="label">{{ $t['requestedBy'] }}</div><div class="value">{{ $voucher->requester?->name ?? '—' }}</div></td>
  </tr>
  <tr>
    <td><div class="label">{{ $t['paymentMethod'] }}</div><div class="value">{{ $voucher->payment_method ?? '—' }}</div></td>
    <td><div class="label">{{ $t['reference'] }}</div><div class="value tnum">{{ $voucher->account_ref ?? '—' }}</div></td>
    <td><div class="label">{{ $t['category'] }}</div><div class="value">{{ $voucher->category ?? '—' }}</div></td>
    <td><div class="label">{{ $t['costCentre'] }}</div><div class="value">{{ $voucher->cost_centre ?? '—' }}</div></td>
  </tr>
</table>

{{-- ──────────────────────────────── purpose ─────────────────────────────── --}}
<div style="padding: 9pt 0;" class="rule-light">
  <div class="kicker">{{ $t['paymentPurpose'] }}</div>
  <div class="purpose-title">{{ $voucher->purpose }}</div>
  @if ($voucher->description)
    <div style="color:#444141;">{{ $voucher->description }}</div>
  @endif
</div>

{{-- ───────────────────────────────── amount ─────────────────────────────── --}}
<table class="rule-heavy" style="padding: 9pt 0;">
  <tr>
    <td style="width: 62%;">
      <div class="kicker">{{ $t['amountWords'] }}</div>
      <div class="amount-words">{{ $voucher->amount_in_words }}</div>
    </td>
    <td style="width: 38%;">
      <div class="kicker" style="text-align: right;">{{ $t['totalPayable'] }}</div>
      <div class="amount-figure tnum">{{ $amountText }}</div>
    </td>
  </tr>
</table>

{{-- ────────────────────────── authorisation ─────────────────────────────
     One block per participant the workflow actually defines, so a four-step
     tenant prints four marks and a single-approver tenant prints two. --}}
<div class="kicker" style="margin: 12pt 0 6pt;">{{ $t['authorisation'] }}</div>
<table>
  <tr>
    @foreach ($signatories as $index => $block)
      <td class="sig-cell">
        <div class="sig-box">
          @if ($block['signature'])
            <img src="{{ $block['signature'] }}" alt="">
          @endif
        </div>
        <div class="sig-label">{{ $block['label'] }}</div>
        <div class="sig-name">{{ $block['name'] ?? '—' }}</div>
        <div class="sig-meta">{{ $block['meta'] }}</div>
      </td>
      @if (($index + 1) % 3 === 0 && ! $loop->last)
    </tr><tr>
      @endif
    @endforeach
  </tr>
</table>

{{-- ─────────────────────────────── attachments ──────────────────────────── --}}
@if ($voucher->attachments->isNotEmpty())
  <div class="rule-light" style="margin-top: 14pt;"></div>
  <div class="kicker" style="margin: 8pt 0 3pt;">{{ $t['attachments'] }}</div>
  <table class="attach">
    @foreach ($voucher->attachments as $attachment)
      <tr>
        <td style="width: 70%;">{{ $loop->iteration }}. {{ $attachment->original_name }}</td>
        <td style="width: 30%; text-align: right;" class="muted">{{ $attachment->humanSize() }}</td>
      </tr>
    @endforeach
  </table>
@endif

{{-- ────────────────────────────────── footer ────────────────────────────── --}}
<div class="foot">
  <table>
    <tr>
      <td style="width: 62%;">
        {{ $company->voucher_footer_text }}
        @if ($voucher->verification_code)
          <br>{{ $t['verificationCode'] }}: <span class="tnum">{{ $voucher->verification_code }}</span>
        @endif
      </td>
      <td style="width: 38%; text-align: right;">
        {{ $t['original'] }}<br>
        {{ $t['generated'] }} {{ $generatedAt }}
      </td>
    </tr>
  </table>
</div>

</body>
</html>
