{{--
  Payment acknowledgement — printed by the cashier and signed by whoever takes
  the money, then scanned back onto the voucher as a supporting document.

  One sheet per payment: a voucher paid in parts has one acknowledgement for
  each part, each stating only what changed hands that time and what is still
  outstanding, so nobody can later be shown to have received more than they
  did. Tables and fixed widths only — DomPDF has no flexbox or grid.
--}}
@php
    $ink = '#0b1220';
    $rule = '#d9dee8';
    $muted = '#6b7689';
    $wash = '#f4f7fb';
    $brand = $company?->primary_color ?: '#2E3192';
    $sw = $locale === 'sw';
    $cash = $voucher->isCash();
@endphp
<!DOCTYPE html>
<html lang="{{ $locale }}">
<head>
    <meta charset="utf-8">
    <title>{{ $payment->reference() }}</title>
    <style>
        @page { size: A4 portrait; margin: 14mm 14mm 12mm; }
        body { font-family: "DejaVu Sans", sans-serif; font-size: 9pt; color: {{ $ink }}; margin: 0; }
        table { border-collapse: collapse; width: 100%; }
        td, th { vertical-align: top; }
        .brandrule { height: 3pt; background: {{ $brand }}; margin-bottom: 10pt; }
        .label { font-size: 6pt; letter-spacing: .11em; text-transform: uppercase; color: {{ $muted }}; font-weight: bold; }
        .muted { color: {{ $muted }}; }
        .strong { font-weight: bold; }
        .company { font-size: 14pt; font-weight: bold; }
        .title { font-size: 12pt; font-weight: bold; letter-spacing: .06em; text-align: right; }
        .ref { font-size: 11pt; font-weight: bold; text-align: right; }
        .grid td { border: 1pt solid {{ $rule }}; padding: 6pt 8pt; }
        .amount { border: 1.5pt solid {{ $ink }}; padding: 10pt 12pt; margin: 12pt 0; }
        .amount-figure { font-size: 18pt; font-weight: bold; }
        .words { font-style: italic; margin-top: 3pt; }
        .statement { background: {{ $wash }}; border-left: 3pt solid {{ $brand }}; padding: 9pt 11pt; line-height: 1.55; margin: 12pt 0; }
        .sigbox { border: 1pt solid {{ $rule }}; padding: 8pt 10pt; height: 150pt; }
        .line { border-bottom: 1pt solid {{ $ink }}; height: 22pt; }
        .sigimg { height: 34pt; }
        .footer { margin-top: 14pt; font-size: 7pt; color: {{ $muted }}; }
        .balance-due { color: #a3183a; font-weight: bold; }
    </style>
</head>
<body>
    <div class="brandrule"></div>

    <table>
        <tr>
            <td style="width: 60%;">
                @if ($logo)
                    <img src="{{ $logo }}" style="height: 34pt; margin-bottom: 4pt;"><br>
                @endif
                <div class="company">{{ $company?->name }}</div>
                <div class="muted">{{ collect([$company?->address, $company?->phone, $company?->tin ? 'TIN '.$company->tin : null])->filter()->implode(' · ') }}</div>
            </td>
            <td style="width: 40%;">
                <div class="title">{{ $cash ? ($sw ? 'UTHIBITISHO WA KUPOKEA FEDHA TASLIMU' : 'CASH PAYMENT ACKNOWLEDGEMENT') : ($sw ? 'UTHIBITISHO WA KUPOKEA MALIPO' : 'PAYMENT ACKNOWLEDGEMENT') }}</div>
                <div class="ref">{{ $payment->reference() }}</div>
                <div class="muted" style="text-align: right;">
                    {{ $sw ? 'Malipo' : 'Payment' }} {{ $payment->sequence }}{{ $partsTotal > 1 || $balanceAfter > 0 ? ($sw ? ' ya vocha hii' : ' on this voucher') : '' }}
                </div>
            </td>
        </tr>
    </table>

    <table class="grid" style="margin-top: 12pt;">
        <tr>
            <td style="width: 33%;"><div class="label">{{ $sw ? 'Namba ya vocha' : 'Voucher no.' }}</div>{{ $voucher->number }}</td>
            <td style="width: 33%;"><div class="label">{{ $sw ? 'Tarehe ya malipo' : 'Payment date' }}</div>{{ $payment->payment_date?->format('j M Y') ?? $payment->paid_at->format('j M Y') }}</td>
            <td style="width: 34%;"><div class="label">{{ $sw ? 'Idara' : 'Department' }}</div>{{ $voucher->department?->name ?? '—' }}</td>
        </tr>
        <tr>
            <td colspan="2"><div class="label">{{ $sw ? 'Madhumuni' : 'Purpose' }}</div>{{ $voucher->purpose }}</td>
            <td><div class="label">{{ $sw ? 'Mlipwaji' : 'Payee' }}</div>{{ $voucher->payee }}</td>
        </tr>
        <tr>
            <td><div class="label">{{ $sw ? 'Kiasi kilichoidhinishwa' : 'Approved amount' }}</div>{{ $fmt($voucher->amount) }}</td>
            <td><div class="label">{{ $sw ? 'Kilicholipwa awali' : 'Paid before this payment' }}</div>{{ $fmt($paidBefore) }}</td>
            <td><div class="label">{{ $sw ? 'Salio baada ya malipo haya' : 'Balance after this payment' }}</div>
                <span class="{{ $balanceAfter > 0 ? 'balance-due' : '' }}">{{ $fmt($balanceAfter) }}</span></td>
        </tr>
        <tr>
            <td><div class="label">{{ $sw ? 'Njia ya malipo' : 'Method' }}</div>{{ $payment->payment_method ?? ($cash ? 'Cash' : 'Bank transfer') }}</td>
            <td><div class="label">{{ $sw ? 'Kumbukumbu' : 'Reference' }}</div>{{ $payment->payment_reference ?? '—' }}</td>
            <td><div class="label">{{ $sw ? 'Kutoka akiba' : 'Float' }}</div>{{ $voucher->cash_float ?? '—' }}</td>
        </tr>
    </table>

    <div class="amount">
        <div class="label">{{ $sw ? 'Kiasi kilichopokelewa sasa' : 'Amount received now' }}</div>
        <div class="amount-figure">{{ $fmt($payment->amount) }}</div>
        <div class="words">{{ $amountWords }}</div>
    </div>

    <div class="statement">
        @if ($sw)
            Mimi, <strong>{{ $payment->received_by ?: '______________________________' }}</strong>, nathibitisha kwamba nimepokea
            <strong>{{ $fmt($payment->amount) }}</strong> ({{ $amountWords }}){{ $cash ? ' taslimu' : '' }} kutoka kwa
            <strong>{{ $payment->paidBy?->name }}</strong> kwa niaba ya {{ $company?->name }}, kwa ajili ya vocha {{ $voucher->number }}.
            @if ($balanceAfter > 0)
                Salio la <strong>{{ $fmt($balanceAfter) }}</strong> bado halijalipwa, na litalipwa kwa uthibitisho tofauti.
            @endif
        @else
            I, <strong>{{ $payment->received_by ?: '______________________________' }}</strong>, confirm that I have received
            <strong>{{ $fmt($payment->amount) }}</strong> ({{ $amountWords }}){{ $cash ? ' in cash' : '' }} from
            <strong>{{ $payment->paidBy?->name }}</strong> on behalf of {{ $company?->name }}, against voucher {{ $voucher->number }}.
            @if ($balanceAfter > 0)
                A balance of <strong>{{ $fmt($balanceAfter) }}</strong> remains outstanding and will be acknowledged separately when paid.
            @else
                This settles the voucher in full.
            @endif
        @endif
    </div>

    <table>
        <tr>
            <td style="width: 49%;">
                <div class="sigbox">
                    <div class="label">{{ $sw ? 'Aliyepokea' : 'Received by' }}</div>
                    <table style="margin-top: 6pt;">
                        <tr><td style="width: 38%;" class="muted">{{ $sw ? 'Jina' : 'Name' }}</td><td class="strong">{{ $payment->received_by ?: '' }}<div class="{{ $payment->received_by ? '' : 'line' }}"></div></td></tr>
                        <tr><td class="muted">{{ $sw ? 'Namba ya kitambulisho / mfanyakazi' : 'ID / employee no.' }}</td><td>{{ $payment->receiver_id_number }}<div class="{{ $payment->receiver_id_number ? '' : 'line' }}"></div></td></tr>
                        <tr><td class="muted">{{ $sw ? 'Sahihi' : 'Signature' }}</td><td><div class="line" style="height: 34pt;"></div></td></tr>
                        <tr><td class="muted">{{ $sw ? 'Tarehe na saa' : 'Date & time' }}</td><td><div class="line"></div></td></tr>
                    </table>
                </div>
            </td>
            <td style="width: 2%;"></td>
            <td style="width: 49%;">
                <div class="sigbox">
                    <div class="label">{{ $sw ? 'Aliyelipa (Mhazini)' : 'Paid by (cashier)' }}</div>
                    <table style="margin-top: 6pt;">
                        <tr><td style="width: 38%;" class="muted">{{ $sw ? 'Jina' : 'Name' }}</td><td class="strong">{{ $payment->paidBy?->name }}</td></tr>
                        <tr><td class="muted">{{ $sw ? 'Cheo' : 'Title' }}</td><td>{{ $payment->paidBy?->job_title ?: ($payment->paidBy ? \App\Models\User::roleLabel($payment->paidBy->role) : '') }}</td></tr>
                        <tr><td class="muted">{{ $sw ? 'Sahihi' : 'Signature' }}</td><td>
                            @if ($cashierSignature)
                                <img class="sigimg" src="{{ $cashierSignature }}">
                            @else
                                <div class="line" style="height: 34pt;"></div>
                            @endif
                        </td></tr>
                        <tr><td class="muted">{{ $sw ? 'Tarehe na saa' : 'Date & time' }}</td><td>{{ $payment->paid_at->timezone($timezone)->format('j M Y, H:i') }}</td></tr>
                    </table>
                </div>
            </td>
        </tr>
    </table>

    <div class="footer">
        {{ $sw ? 'Imetolewa na VouchFlow' : 'Generated by VouchFlow' }} · {{ $generatedAt }} ·
        {{ $sw ? 'Rudisha nakala iliyosainiwa kwa mhazini ili iambatishwe kwenye vocha' : 'Return the signed copy to the cashier to be attached to the voucher' }} {{ $voucher->number }}.
    </div>
</body>
</html>
