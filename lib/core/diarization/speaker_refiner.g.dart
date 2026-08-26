// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'speaker_refiner.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(speakerRefiner)
final speakerRefinerProvider = SpeakerRefinerProvider._();

final class SpeakerRefinerProvider
    extends $FunctionalProvider<SpeakerRefiner, SpeakerRefiner, SpeakerRefiner>
    with $Provider<SpeakerRefiner> {
  SpeakerRefinerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'speakerRefinerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$speakerRefinerHash();

  @$internal
  @override
  $ProviderElement<SpeakerRefiner> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SpeakerRefiner create(Ref ref) {
    return speakerRefiner(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SpeakerRefiner value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SpeakerRefiner>(value),
    );
  }
}

String _$speakerRefinerHash() => r'1976fedd25deb8709a02b0333ea80d43bd160ca3';
