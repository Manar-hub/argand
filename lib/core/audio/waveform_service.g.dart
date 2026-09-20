// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'waveform_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(waveformService)
final waveformServiceProvider = WaveformServiceProvider._();

final class WaveformServiceProvider
    extends
        $FunctionalProvider<WaveformService, WaveformService, WaveformService>
    with $Provider<WaveformService> {
  WaveformServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'waveformServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$waveformServiceHash();

  @$internal
  @override
  $ProviderElement<WaveformService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  WaveformService create(Ref ref) {
    return waveformService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WaveformService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WaveformService>(value),
    );
  }
}

String _$waveformServiceHash() => r'2af509841c1e21d02d77a7bf97c4abcbdf661145';
