// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shared_media.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(sharedMediaChannel)
final sharedMediaChannelProvider = SharedMediaChannelProvider._();

final class SharedMediaChannelProvider
    extends
        $FunctionalProvider<
          SharedMediaChannel,
          SharedMediaChannel,
          SharedMediaChannel
        >
    with $Provider<SharedMediaChannel> {
  SharedMediaChannelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sharedMediaChannelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sharedMediaChannelHash();

  @$internal
  @override
  $ProviderElement<SharedMediaChannel> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SharedMediaChannel create(Ref ref) {
    return sharedMediaChannel(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SharedMediaChannel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SharedMediaChannel>(value),
    );
  }
}

String _$sharedMediaChannelHash() =>
    r'2b426f36f944ea21681631d52955542e6ef80871';
