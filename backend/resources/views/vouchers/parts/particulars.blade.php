{{--
  The payment particulars as term/value rows.
  @include('vouchers.parts.particulars', ['doc' => $doc, 'termWidth' => '42%', 'rowStyle' => '...', 'termStyle' => '...', 'valueStyle' => '...', 'skipAmount' => false])
--}}
@php
    $rows = $doc['particulars'];
    if (! empty($skipAmount)) { $rows = array_slice($rows, 1); }
@endphp
<table>
    @foreach ($rows as [$term, $value])
        <tr>
            <td style="width: {{ $termWidth ?? '42%' }}; {{ $rowStyle ?? '' }} {{ $termStyle ?? '' }}">{{ $term }}</td>
            <td style="{{ $rowStyle ?? '' }} {{ $valueStyle ?? '' }} {{ ($loop->first && empty($skipAmount)) ? 'font-weight: bold;' : '' }}">{{ $value }}</td>
        </tr>
    @endforeach
</table>
