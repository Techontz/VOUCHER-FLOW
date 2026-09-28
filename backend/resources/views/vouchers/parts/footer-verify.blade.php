{{-- The footer's working half: the words that make it valid and how to check it. --}}
{{ $doc['company']['footer_text'] }}
@if ($doc['voucher']['verification_code'])
    <br>{{ $doc['t']['verificationCode'] }}: <span class="b">{{ $doc['voucher']['verification_code'] }}</span>
@endif
