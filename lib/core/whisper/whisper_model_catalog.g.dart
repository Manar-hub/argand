// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'whisper_model_catalog.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(whisperModelCatalog)
final whisperModelCatalogProvider = WhisperModelCatalogProvider._();

final class WhisperModelCatalogProvider
    extends
        $FunctionalProvider<
          WhisperModelCatalog,
          WhisperModelCatalog,
          WhisperModelCatalog
        >
    with $Provider<WhisperModelCatalog> {
  WhisperModelCatalogProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'whisperModelCatalogProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$whisperModelCatalogHash();

  @$internal
  @override
  $ProviderElement<WhisperModelCatalog> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WhisperModelCatalog create(Ref ref) {
    return whisperModelCatalog(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WhisperModelCatalog value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WhisperModelCatalog>(value),
    );
  }
}

String _$whisperModelCatalogHash() =>
    r'95c77b14f8ade2ff15d8de964a955bc6622c941f';

/// Models offered in the picker: the ones this build ships and that are on the
/// device -- the install-time default, and any on-demand model added in
/// Settings -> Transcription models.

@ProviderFor(availableWhisperModels)
final availableWhisperModelsProvider = AvailableWhisperModelsProvider._();

/// Models offered in the picker: the ones this build ships and that are on the
/// device -- the install-time default, and any on-demand model added in
/// Settings -> Transcription models.

final class AvailableWhisperModelsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<WhisperModelDescriptor>>,
          List<WhisperModelDescriptor>,
          FutureOr<List<WhisperModelDescriptor>>
        >
    with
        $FutureModifier<List<WhisperModelDescriptor>>,
        $FutureProvider<List<WhisperModelDescriptor>> {
  /// Models offered in the picker: the ones this build ships and that are on the
  /// device -- the install-time default, and any on-demand model added in
  /// Settings -> Transcription models.
  AvailableWhisperModelsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'availableWhisperModelsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$availableWhisperModelsHash();

  @$internal
  @override
  $FutureProviderElement<List<WhisperModelDescriptor>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<WhisperModelDescriptor>> create(Ref ref) {
    return availableWhisperModels(ref);
  }
}

String _$availableWhisperModelsHash() =>
    r'c29e0338f64185918bb930158d4f1316d078a17e';
