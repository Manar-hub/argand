// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_converter.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mediaConverter)
final mediaConverterProvider = MediaConverterProvider._();

final class MediaConverterProvider
    extends $FunctionalProvider<MediaConverter, MediaConverter, MediaConverter>
    with $Provider<MediaConverter> {
  MediaConverterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mediaConverterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mediaConverterHash();

  @$internal
  @override
  $ProviderElement<MediaConverter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MediaConverter create(Ref ref) {
    return mediaConverter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MediaConverter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MediaConverter>(value),
    );
  }
}

String _$mediaConverterHash() => r'f2ff8050445dfb62b23156247ad017308408e815';
