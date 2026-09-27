// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(translator)
final translatorProvider = TranslatorProvider._();

final class TranslatorProvider
    extends $FunctionalProvider<Translator, Translator, Translator>
    with $Provider<Translator> {
  TranslatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translatorHash();

  @$internal
  @override
  $ProviderElement<Translator> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Translator create(Ref ref) {
    return translator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Translator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Translator>(value),
    );
  }
}

String _$translatorHash() => r'e37f35221cc3878364081f37f08f464ba7fd1e4e';

/// The language a new transcription is also translated into, or null for
/// none -- the Transcribe sheet's "Translate to". Also what the Translate
/// sheet offers first.

@ProviderFor(TranslationTarget)
final translationTargetProvider = TranslationTargetProvider._();

/// The language a new transcription is also translated into, or null for
/// none -- the Transcribe sheet's "Translate to". Also what the Translate
/// sheet offers first.
final class TranslationTargetProvider
    extends $AsyncNotifierProvider<TranslationTarget, String?> {
  /// The language a new transcription is also translated into, or null for
  /// none -- the Transcribe sheet's "Translate to". Also what the Translate
  /// sheet offers first.
  TranslationTargetProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationTargetProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationTargetHash();

  @$internal
  @override
  TranslationTarget create() => TranslationTarget();
}

String _$translationTargetHash() => r'1cc4933367edf1029b300120e38c22c6816a9445';

/// The language a new transcription is also translated into, or null for
/// none -- the Transcribe sheet's "Translate to". Also what the Translate
/// sheet offers first.

abstract class _$TranslationTarget extends $AsyncNotifier<String?> {
  FutureOr<String?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<String?>, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<String?>, String?>,
              AsyncValue<String?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
