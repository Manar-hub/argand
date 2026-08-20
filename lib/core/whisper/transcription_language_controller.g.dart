// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcription_language_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The language the next transcription will use, persisted across launches.

@ProviderFor(SelectedTranscriptionLanguage)
final selectedTranscriptionLanguageProvider =
    SelectedTranscriptionLanguageProvider._();

/// The language the next transcription will use, persisted across launches.
final class SelectedTranscriptionLanguageProvider
    extends
        $AsyncNotifierProvider<
          SelectedTranscriptionLanguage,
          TranscriptionLanguage
        > {
  /// The language the next transcription will use, persisted across launches.
  SelectedTranscriptionLanguageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedTranscriptionLanguageProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedTranscriptionLanguageHash();

  @$internal
  @override
  SelectedTranscriptionLanguage create() => SelectedTranscriptionLanguage();
}

String _$selectedTranscriptionLanguageHash() =>
    r'022c0426dd5efa0ae8cc9845e0cfbc57ac40bc54';

/// The language the next transcription will use, persisted across launches.

abstract class _$SelectedTranscriptionLanguage
    extends $AsyncNotifier<TranscriptionLanguage> {
  FutureOr<TranscriptionLanguage> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<TranscriptionLanguage>, TranscriptionLanguage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<TranscriptionLanguage>,
                TranscriptionLanguage
              >,
              AsyncValue<TranscriptionLanguage>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
