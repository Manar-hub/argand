// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'whisper_model_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The transcription model the app will use, persisted across launches.

@ProviderFor(SelectedWhisperModel)
final selectedWhisperModelProvider = SelectedWhisperModelProvider._();

/// The transcription model the app will use, persisted across launches.
final class SelectedWhisperModelProvider
    extends
        $AsyncNotifierProvider<SelectedWhisperModel, WhisperModelDescriptor?> {
  /// The transcription model the app will use, persisted across launches.
  SelectedWhisperModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedWhisperModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedWhisperModelHash();

  @$internal
  @override
  SelectedWhisperModel create() => SelectedWhisperModel();
}

String _$selectedWhisperModelHash() =>
    r'08333236fd6a8b73751467c420d486b09db968d8';

/// The transcription model the app will use, persisted across launches.

abstract class _$SelectedWhisperModel
    extends $AsyncNotifier<WhisperModelDescriptor?> {
  FutureOr<WhisperModelDescriptor?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<WhisperModelDescriptor?>,
              WhisperModelDescriptor?
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<WhisperModelDescriptor?>,
                WhisperModelDescriptor?
              >,
              AsyncValue<WhisperModelDescriptor?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
