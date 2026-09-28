// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'asset_packs_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every model this build ships, installed or not, each with what its file
/// says about itself.
///
/// **Adding a model is dropping its file in.** Any `ggml-<id>.bin` or
/// `whisper-<id>.gguf` put in `assets/models/` is listed after the next build, as an on-demand pack;
/// adding it here delivers it, and its header decides whether it is ready.

@ProviderFor(modelPacks)
final modelPacksProvider = ModelPacksProvider._();

/// Every model this build ships, installed or not, each with what its file
/// says about itself.
///
/// **Adding a model is dropping its file in.** Any `ggml-<id>.bin` or
/// `whisper-<id>.gguf` put in `assets/models/` is listed after the next build, as an on-demand pack;
/// adding it here delivers it, and its header decides whether it is ready.

final class ModelPacksProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ModelPackEntry>>,
          List<ModelPackEntry>,
          FutureOr<List<ModelPackEntry>>
        >
    with
        $FutureModifier<List<ModelPackEntry>>,
        $FutureProvider<List<ModelPackEntry>> {
  /// Every model this build ships, installed or not, each with what its file
  /// says about itself.
  ///
  /// **Adding a model is dropping its file in.** Any `ggml-<id>.bin` or
  /// `whisper-<id>.gguf` put in `assets/models/` is listed after the next build, as an on-demand pack;
  /// adding it here delivers it, and its header decides whether it is ready.
  ModelPacksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modelPacksProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modelPacksHash();

  @$internal
  @override
  $FutureProviderElement<List<ModelPackEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ModelPackEntry>> create(Ref ref) {
    return modelPacks(ref);
  }
}

String _$modelPacksHash() => r'fda8333fb6adab8d52620a21ead163aaaa4542c2';

/// Every translation language, which are on the device first.

@ProviderFor(languagePacks)
final languagePacksProvider = LanguagePacksProvider._();

/// Every translation language, which are on the device first.

final class LanguagePacksProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LanguagePackEntry>>,
          List<LanguagePackEntry>,
          FutureOr<List<LanguagePackEntry>>
        >
    with
        $FutureModifier<List<LanguagePackEntry>>,
        $FutureProvider<List<LanguagePackEntry>> {
  /// Every translation language, which are on the device first.
  LanguagePacksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'languagePacksProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$languagePacksHash();

  @$internal
  @override
  $FutureProviderElement<List<LanguagePackEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<LanguagePackEntry>> create(Ref ref) {
    return languagePacks(ref);
  }
}

String _$languagePacksHash() => r'a7e8ccc068c1db99d05aad3c2b74918e9bb679bf';

/// Packs being fetched right now, by name -- what the screens draw progress
/// from. Kept alive, so a download carries on when its screen is left, as a
/// real store download does.

@ProviderFor(AssetPackProgress)
final assetPackProgressProvider = AssetPackProgressProvider._();

/// Packs being fetched right now, by name -- what the screens draw progress
/// from. Kept alive, so a download carries on when its screen is left, as a
/// real store download does.
final class AssetPackProgressProvider
    extends $NotifierProvider<AssetPackProgress, Map<String, AssetPackState>> {
  /// Packs being fetched right now, by name -- what the screens draw progress
  /// from. Kept alive, so a download carries on when its screen is left, as a
  /// real store download does.
  AssetPackProgressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'assetPackProgressProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$assetPackProgressHash();

  @$internal
  @override
  AssetPackProgress create() => AssetPackProgress();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AssetPackState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AssetPackState>>(value),
    );
  }
}

String _$assetPackProgressHash() => r'd3a844ef3dc8ecce7c7199f30a5c29389f495a24';

/// Packs being fetched right now, by name -- what the screens draw progress
/// from. Kept alive, so a download carries on when its screen is left, as a
/// real store download does.

abstract class _$AssetPackProgress
    extends $Notifier<Map<String, AssetPackState>> {
  Map<String, AssetPackState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<Map<String, AssetPackState>, Map<String, AssetPackState>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, AssetPackState>,
                Map<String, AssetPackState>
              >,
              Map<String, AssetPackState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
