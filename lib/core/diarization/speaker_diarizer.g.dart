// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'speaker_diarizer.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(speakerDiarizer)
final speakerDiarizerProvider = SpeakerDiarizerProvider._();

final class SpeakerDiarizerProvider
    extends
        $FunctionalProvider<SpeakerDiarizer, SpeakerDiarizer, SpeakerDiarizer>
    with $Provider<SpeakerDiarizer> {
  SpeakerDiarizerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'speakerDiarizerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$speakerDiarizerHash();

  @$internal
  @override
  $ProviderElement<SpeakerDiarizer> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SpeakerDiarizer create(Ref ref) {
    return speakerDiarizer(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SpeakerDiarizer value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SpeakerDiarizer>(value),
    );
  }
}

String _$speakerDiarizerHash() => r'6ef475de5caf07df547ffb25b94fb7f909388583';
