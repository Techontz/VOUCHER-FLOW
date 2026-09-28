{{-- The company account a bank voucher is drawn on. Nothing for cash. --}}
@if ($doc['voucher']['kind'] === 'bank' && $doc['company']['bank'])
    @php $bank = $doc['company']['bank']; @endphp
    <div style="{{ $labelStyle ?? '' }}">{{ $doc['t']['drawnOn'] }}</div>
    <div class="b" style="margin-top: 1pt;">{{ $bank['name'] }}</div>
    <div class="muted" style="font-size: 7.5pt;">{{ $bank['account_name'] }}</div>
    <div class="muted" style="font-size: 7.5pt;">{{ collect([$bank['account_number'], $bank['branch']])->filter()->implode(' · ') }}</div>
@endif
