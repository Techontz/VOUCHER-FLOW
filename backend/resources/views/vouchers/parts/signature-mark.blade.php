{{--
  The signature image and stamp for one signatory, centred in a fixed-height
  area so every block in a row lines up whether or not it has been signed.
  @include('vouchers.parts.signature-mark', ['doc' => $doc, 's' => $s, 'height' => 34])
--}}
@php $height = $height ?? 34; @endphp
<div style="height: {{ $height }}pt; text-align: {{ $align ?? 'center' }}; overflow: hidden;">
    @if ($s['signature'])
        <img src="{{ $s['signature'] }}" alt="" style="max-height: {{ round($height * 0.5) }}pt; max-width: 80pt;"><br>
    @endif
    @include('vouchers.parts.stamp', ['kind' => $s['stamp']])
</div>
