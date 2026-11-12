{{--
  A payslip: one person, one month, every figure it was paid on, read from
  the payslip row itself so a later contract or rate change never alters it.
  Tables and fixed widths only: DomPDF has no flexbox or grid.
--}}
@php
    $ink = '#0b1220';
    $rule = '#d9dee8';
    $muted = '#6b7689';
    $brand = $company?->primary_color ?: '#2E3192';
    $money = fn ($v) => number_format((float) $v, 2);
    $lines = $slip->lines ?? [];
    $earnings = array_filter([
        ['Basic salary', $slip->basic],
        ['Housing allowance', $slip->housing_allowance],
        ['Transport allowance', $slip->transport_allowance],
        ['Other allowance', $slip->other_allowance],
        ['Overtime ('.(float) $slip->overtime_hours.' h)', $slip->overtime],
        ...array_map(fn ($l) => [$l['description'], $l['amount']], $lines['earnings'] ?? []),
        ['Less absence and unpaid leave ('.(float) $slip->unpaid_days.' days)', -1 * (float) $slip->absence_deduction],
    ], fn ($r) => (float) $r[1] != 0);
    $deductions = array_filter([
        ['NSSF (employee)', $slip->nssf_employee],
        ['PAYE', $slip->paye],
        ['HESLB', $slip->heslb],
        ...array_map(fn ($l) => ['Loan '.$l['number'], $l['amount']], $lines['loans'] ?? []),
        ...array_map(fn ($l) => [$l['description'], $l['amount']], $lines['deductions'] ?? []),
    ], fn ($r) => (float) $r[1] != 0);
    $month = \Illuminate\Support\Carbon::parse($run->period.'-01')->format('F Y');
@endphp
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>Payslip {{ $slip->employee_number }} {{ $run->period }}</title>
    <style>
        @page { size: A4 portrait; margin: 14mm; }
        body { font-family: "DejaVu Sans", sans-serif; font-size: 9pt; color: {{ $ink }}; margin: 0; }
        table { border-collapse: collapse; width: 100%; }
        td, th { vertical-align: top; padding: 4pt 6pt; }
        .brandrule { height: 3pt; background: {{ $brand }}; margin-bottom: 10pt; }
        .label { font-size: 6.5pt; letter-spacing: .1em; text-transform: uppercase; color: {{ $muted }}; font-weight: bold; }
        .company { font-size: 14pt; font-weight: bold; }
        .title { font-size: 12pt; font-weight: bold; text-align: right; }
        .grid td { border: 1pt solid {{ $rule }}; }
        .num { text-align: right; font-variant-numeric: tabular-nums; }
        .head th { text-align: left; border-bottom: 1.5pt solid {{ $ink }}; font-size: 8pt; }
        .total td { border-top: 1pt solid {{ $ink }}; font-weight: bold; }
        .net { border: 1.5pt solid {{ $ink }}; padding: 10pt; margin-top: 12pt; font-size: 13pt; font-weight: bold; }
        .muted { color: {{ $muted }}; }
    </style>
</head>
<body>
    <div class="brandrule"></div>
    <table>
        <tr>
            <td style="padding:0"><div class="company">{{ $company?->name }}</div><div class="muted">{{ $company?->address }}</div></td>
            <td style="padding:0" class="title">PAYSLIP<br><span class="muted" style="font-size:9pt">{{ $month }} · {{ $run->number }}</span></td>
        </tr>
    </table>

    <table class="grid" style="margin-top:12pt">
        <tr>
            <td style="width:50%"><div class="label">Employee</div>{{ $slip->employee_name }} ({{ $slip->employee_number }})</td>
            <td><div class="label">Department / title</div>{{ $slip->department ?? '-' }} · {{ $slip->job_title ?? '-' }}</td>
        </tr>
        <tr>
            <td><div class="label">Bank</div>{{ $slip->bank_name ?? '-' }} {{ $slip->bank_account_number }}</td>
            <td><div class="label">Days paid</div>{{ (float) $slip->days_paid }}</td>
        </tr>
        <tr>
            <td><div class="label">TIN / NSSF</div>{{ $slip->employee?->tin ?? '-' }} / {{ $slip->employee?->nssf_number ?? '-' }}</td>
            <td><div class="label">Taxable pay</div>{{ $money($slip->taxable) }}</td>
        </tr>
    </table>

    <table style="margin-top:12pt">
        <tr>
            <td style="width:50%; padding:0 6pt 0 0">
                <table>
                    <tr class="head"><th>Earnings</th><th class="num">TZS</th></tr>
                    @foreach ($earnings as [$label, $value])
                        <tr><td>{{ $label }}</td><td class="num">{{ $money($value) }}</td></tr>
                    @endforeach
                    <tr class="total"><td>Gross pay</td><td class="num">{{ $money($slip->gross) }}</td></tr>
                </table>
            </td>
            <td style="width:50%; padding:0 0 0 6pt">
                <table>
                    <tr class="head"><th>Deductions</th><th class="num">TZS</th></tr>
                    @foreach ($deductions as [$label, $value])
                        <tr><td>{{ $label }}</td><td class="num">{{ $money($value) }}</td></tr>
                    @endforeach
                    <tr class="total"><td>Total deductions</td><td class="num">{{ $money($slip->total_deductions) }}</td></tr>
                </table>
            </td>
        </tr>
    </table>

    <div class="net">Net pay: TZS {{ $money($slip->net) }}</div>

    <table style="margin-top:12pt">
        <tr class="head"><th>Employer contributions (not deducted)</th><th class="num">TZS</th></tr>
        <tr><td>NSSF (employer)</td><td class="num">{{ $money($slip->nssf_employer) }}</td></tr>
        <tr><td>WCF</td><td class="num">{{ $money($slip->wcf) }}</td></tr>
        <tr><td>SDL</td><td class="num">{{ $money($slip->sdl) }}</td></tr>
    </table>

    <p class="muted" style="margin-top:18pt; font-size:7.5pt">Generated {{ now()->format('d M Y H:i') }}. Gross pay is after absence and unpaid leave; NSSF, PAYE and HESLB are calculated on it.</p>
</body>
</html>
