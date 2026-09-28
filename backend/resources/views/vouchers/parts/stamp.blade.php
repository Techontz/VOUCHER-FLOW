{{-- A person's mark: signed, approved, paid or rejected. --}}
@if (! empty($kind))
    <span class="vf-stamp vf-stamp-{{ $kind }}">{{ $doc['t'][$kind] ?? $kind }}</span>
@endif
