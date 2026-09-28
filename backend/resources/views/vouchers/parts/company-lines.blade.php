{{-- Address and contact lines under the company name. --}}
@foreach ($doc['company']['lines'] as $line)
    {{ $line }}@if (! $loop->last)<br>@endif
@endforeach
