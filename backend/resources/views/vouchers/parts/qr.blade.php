{{--
  A real, scannable QR code of the verification code, drawn as table cells so
  DomPDF and the browser render identical crisp modules.
  @include('vouchers.parts.qr', ['doc' => $doc, 'cell' => 2.2])   // cell = module size in pt
--}}
@if ($doc['qr'])
    @php $cell = $cell ?? 2.2; $quiet = $cell * 2; @endphp
    <table style="width: auto; border-collapse: collapse; table-layout: fixed; background: #fff; {{ $frameStyle ?? '' }}">
        <tr><td style="padding: {{ $quiet }}pt;">
            <table style="width: {{ $cell * $doc['qr']['size'] }}pt; border-collapse: collapse; table-layout: fixed;">
                @foreach ($doc['qr']['cells'] as $row)
                    <tr>
                        @foreach ($row as $on)
                            <td style="width: {{ $cell }}pt; height: {{ $cell }}pt; padding: 0; font-size: 0; line-height: 0;{{ $on ? ' background: #0b1220;' : '' }}"></td>
                        @endforeach
                    </tr>
                @endforeach
            </table>
        </td></tr>
    </table>
@endif
