{{--
  The company's logo, or its initial on the brand colour when none is uploaded.
  @include('vouchers.parts.logo', ['doc' => $doc, 'height' => 40, 'width' => 88, 'inverse' => false])
  `inverse` draws the initial for a dark or coloured band.
--}}
@php
    $height = $height ?? 40;
    $width = $width ?? 88;
    $inverse = $inverse ?? false;
    $b = $doc['brand'];
@endphp
@if ($doc['company']['logo'])
    <img src="{{ $doc['company']['logo'] }}" alt="" style="max-height: {{ $height }}pt; max-width: {{ $width }}pt;">
@else
    <table style="width: {{ $height }}pt;"><tr><td style="width: {{ $height }}pt; height: {{ $height }}pt; text-align: center; vertical-align: middle;
        background: {{ $inverse ? $b['on_secondary'] : $b['primary'] }}; color: {{ $inverse ? $b['secondary'] : $b['on_primary'] }};
        font-weight: bold; font-size: {{ round($height * 0.48) }}pt; border-radius: 3pt;">{{ $doc['company']['initial'] }}</td></tr></table>
@endif
