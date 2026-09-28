{{-- Supporting documents, numbered. --}}
@forelse ($doc['attachments'] as $name)
    <div style="{{ $itemStyle ?? 'font-size: 7.5pt; margin-top: 2pt;' }}">{{ $loop->iteration }}. {{ $name }}</div>
@empty
    <div class="faint" style="{{ $itemStyle ?? 'font-size: 7.5pt; margin-top: 2pt;' }}">{{ $doc['t']['noneAttached'] }}</div>
@endforelse
