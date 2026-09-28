// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delivery_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// How packs reach the device: the fake until the app is on the store.
///
/// Models land in the application support directory, where
/// `WhisperService.modelPath` has always looked, so a model delivered here is
/// the file the engine loads.

@ProviderFor(assetPackDelivery)
final assetPackDeliveryProvider = AssetPackDeliveryProvider._();

/// How packs reach the device: the fake until the app is on the store.
///
/// Models land in the application support directory, where
/// `WhisperService.modelPath` has always looked, so a model delivered here is
/// the file the engine loads.

final class AssetPackDeliveryProvider
    extends
        $FunctionalProvider<
          AssetPackDelivery,
          AssetPackDelivery,
          AssetPackDelivery
        >
    with $Provider<AssetPackDelivery> {
  /// How packs reach the device: the fake until the app is on the store.
  ///
  /// Models land in the application support directory, where
  /// `WhisperService.modelPath` has always looked, so a model delivered here is
  /// the file the engine loads.
  AssetPackDeliveryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'assetPackDeliveryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$assetPackDeliveryHash();

  @$internal
  @override
  $ProviderElement<AssetPackDelivery> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AssetPackDelivery create(Ref ref) {
    return assetPackDelivery(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AssetPackDelivery value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AssetPackDelivery>(value),
    );
  }
}

String _$assetPackDeliveryHash() => r'43a848c60732685d98bf0ed390e11ef3cdee35c9';
