// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_denoiser.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(audioDenoiser)
final audioDenoiserProvider = AudioDenoiserProvider._();

final class AudioDenoiserProvider
    extends $FunctionalProvider<AudioDenoiser, AudioDenoiser, AudioDenoiser>
    with $Provider<AudioDenoiser> {
  AudioDenoiserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'audioDenoiserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$audioDenoiserHash();

  @$internal
  @override
  $ProviderElement<AudioDenoiser> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AudioDenoiser create(Ref ref) {
    return audioDenoiser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AudioDenoiser value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AudioDenoiser>(value),
    );
  }
}

String _$audioDenoiserHash() => r'428df0302ad1a5ef56e60e249661788c82d4b56e';
