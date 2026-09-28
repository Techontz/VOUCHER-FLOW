{{--
  The frame every voucher template sits in.

  One HTML document serves two renderers. DomPDF ($doc['mode'] === 'pdf') gets
  A4 page margins from @page; the browser ('html') gets the same margins as
  padding on a 210mm sheet, so the on-screen document is the printed one.
  DomPDF has no flexbox or grid — templates lay out with tables only.

  The paper is always white and ink-on-paper whatever the interface theme:
  this is a financial document. Brand colour comes only from $doc['brand'].

  Templates @extend this and fill `styles` and `content`; they may set
  @section('font', 'serif') for the serif family.
--}}
@php
    $b = $doc['brand'];
    $t = $doc['t'];
    $html = $doc['mode'] === 'html';
    $sans = '"DejaVu Sans", "Helvetica Neue", Helvetica, Arial, sans-serif';
    $serif = '"DejaVu Serif", Georgia, "Times New Roman", serif';
@endphp
<!DOCTYPE html>
<html lang="{{ $doc['locale'] }}">
<head>
    <meta charset="utf-8">
    <title>{{ $doc['voucher']['number'] }}</title>
    <style>
        @page { size: A4 portrait; margin: @yield('page_margin', '12mm 12mm 10mm'); }

        * { box-sizing: border-box; }
        html { background: #fff; }
        body {
            font-family: {!! trim($__env->yieldContent('font')) === 'serif' ? $serif : $sans !!};
            font-size: 10pt; line-height: 1.4; color: #0b1220; margin: 0;
            -webkit-print-color-adjust: exact; print-color-adjust: exact;
        }
        .serif { font-family: {!! $serif !!}; }
        .sans { font-family: {!! $sans !!}; }

        @if ($html)
            .sheet { width: 210mm; min-height: 297mm; padding: @yield('page_margin', '12mm 12mm 10mm'); position: relative; background: #fff; overflow: hidden; }
            @media print { @page { margin: 0; } .sheet { min-height: 0; } }
        @else
            .sheet { position: relative; }
        @endif

        table { border-collapse: collapse; width: 100%; }
        td, th { vertical-align: top; padding: 0; text-align: left; font-weight: normal; }
        img { border: 0; }
        p { margin: 0; }

        .b { font-weight: bold; }
        .i { font-style: italic; }
        .r { text-align: right; }
        .c { text-align: center; }
        .up { text-transform: uppercase; }
        .nowrap { white-space: nowrap; }
        .muted { color: #5b6678; }
        .faint { color: #8a94a6; }

        /*
         * The type scale every design shares. Readability is a rule, not a
         * preference: nothing on a voucher is set smaller than 7.5pt (the
         * render check fails any template that is), labels are 7.5–8pt,
         * running text 9.5–10.5pt, key values 10.5pt and up.
         */
        .t-label { font-size: 7.5pt; font-weight: bold; letter-spacing: .08em; text-transform: uppercase; color: #5b6678; }
        .t-meta { font-size: 8.5pt; color: #5b6678; }
        .t-body { font-size: 10pt; }
        .t-value { font-size: 10.5pt; font-weight: bold; }
        .t-h { font-size: 12pt; font-weight: bold; }

        /* ── stamps: the ink a person's action leaves on the paper ── */
        .vf-stamp {
            display: inline-block; border: 1.3pt solid currentColor; padding: 1.5pt 6pt;
            font-size: 7.5pt; font-weight: bold; letter-spacing: .12em; text-transform: uppercase;
            font-family: {!! $sans !!};
        }
        .vf-stamp-signed { color: #1f3a8a; }
        .vf-stamp-approved { color: #0f7a54; }
        .vf-stamp-paid { color: #a3183a; }
        .vf-stamp-rejected { color: #a3183a; }

        /* ── the settled-document mark ── */
        .vf-mark {
            position: absolute; top: 88mm; right: 16mm; z-index: 5;
            border: 2.4pt solid currentColor; padding: 4pt 12pt; text-align: center;
            transform: rotate(-12deg); opacity: .55; font-family: {!! $sans !!};
        }
        .vf-mark-word { font-size: 22pt; font-weight: bold; letter-spacing: .14em; text-transform: uppercase; line-height: 1.1; }
        .vf-mark-date { font-size: 8pt; letter-spacing: .08em; }
        .vf-mark-paid { color: #a3183a; }
        .vf-mark-rejected { color: #a3183a; }
        .vf-mark-cancelled { color: #6b7689; }

        @yield('styles')
    </style>
</head>
<body>
<div class="sheet">
    @if ($doc['mark'])
        <div class="vf-mark vf-mark-{{ $doc['mark']['kind'] }}">
            <div class="vf-mark-word">{{ $doc['mark']['label'] }}</div>
            @if ($doc['mark']['date'])<div class="vf-mark-date">{{ $doc['mark']['date'] }}</div>@endif
        </div>
    @endif

    @yield('content')
</div>
</body>
</html>
