// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clip_transcription_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Transcribes one clip, on request.
///
/// **The deliberate half of the split.** Adding a clip is cheap and immediate;
/// this is the part that costs minutes of CPU, so it never starts on its own.
/// Selecting a clip reveals the action, and the user takes it.
///
/// Keyed by clip, so two clips have genuinely independent state: transcribing
/// one does not make another look busy, and a failure is attributable to the
/// clip that caused it.
///
/// Note that a clip's word timings are relative to its own media, and its
/// speaker numbering comes from its own diarization run — labels do not
/// correspond across clips (`docs/engine-architecture.md`).

@ProviderFor(ClipTranscriptionController)
final clipTranscriptionControllerProvider =
    ClipTranscriptionControllerFamily._();

/// Transcribes one clip, on request.
///
/// **The deliberate half of the split.** Adding a clip is cheap and immediate;
/// this is the part that costs minutes of CPU, so it never starts on its own.
/// Selecting a clip reveals the action, and the user takes it.
///
/// Keyed by clip, so two clips have genuinely independent state: transcribing
/// one does not make another look busy, and a failure is attributable to the
/// clip that caused it.
///
/// Note that a clip's word timings are relative to its own media, and its
/// speaker numbering comes from its own diarization run — labels do not
/// correspond across clips (`docs/engine-architecture.md`).
final class ClipTranscriptionControllerProvider
    extends
        $NotifierProvider<
          ClipTranscriptionController,
          ClipTranscriptionStatus
        > {
  /// Transcribes one clip, on request.
  ///
  /// **The deliberate half of the split.** Adding a clip is cheap and immediate;
  /// this is the part that costs minutes of CPU, so it never starts on its own.
  /// Selecting a clip reveals the action, and the user takes it.
  ///
  /// Keyed by clip, so two clips have genuinely independent state: transcribing
  /// one does not make another look busy, and a failure is attributable to the
  /// clip that caused it.
  ///
  /// Note that a clip's word timings are relative to its own media, and its
  /// speaker numbering comes from its own diarization run — labels do not
  /// correspond across clips (`docs/engine-architecture.md`).
  ClipTranscriptionControllerProvider._({
    required ClipTranscriptionControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'clipTranscriptionControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clipTranscriptionControllerHash();

  @override
  String toString() {
    return r'clipTranscriptionControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ClipTranscriptionController create() => ClipTranscriptionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClipTranscriptionStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClipTranscriptionStatus>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClipTranscriptionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clipTranscriptionControllerHash() =>
    r'923054b3084095f46ad055659f68661b2d121243';

/// Transcribes one clip, on request.
///
/// **The deliberate half of the split.** Adding a clip is cheap and immediate;
/// this is the part that costs minutes of CPU, so it never starts on its own.
/// Selecting a clip reveals the action, and the user takes it.
///
/// Keyed by clip, so two clips have genuinely independent state: transcribing
/// one does not make another look busy, and a failure is attributable to the
/// clip that caused it.
///
/// Note that a clip's word timings are relative to its own media, and its
/// speaker numbering comes from its own diarization run — labels do not
/// correspond across clips (`docs/engine-architecture.md`).

final class ClipTranscriptionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ClipTranscriptionController,
          ClipTranscriptionStatus,
          ClipTranscriptionStatus,
          ClipTranscriptionStatus,
          String
        > {
  ClipTranscriptionControllerFamily._()
    : super(
        retry: null,
        name: r'clipTranscriptionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Transcribes one clip, on request.
  ///
  /// **The deliberate half of the split.** Adding a clip is cheap and immediate;
  /// this is the part that costs minutes of CPU, so it never starts on its own.
  /// Selecting a clip reveals the action, and the user takes it.
  ///
  /// Keyed by clip, so two clips have genuinely independent state: transcribing
  /// one does not make another look busy, and a failure is attributable to the
  /// clip that caused it.
  ///
  /// Note that a clip's word timings are relative to its own media, and its
  /// speaker numbering comes from its own diarization run — labels do not
  /// correspond across clips (`docs/engine-architecture.md`).

  ClipTranscriptionControllerProvider call(String clipId) =>
      ClipTranscriptionControllerProvider._(argument: clipId, from: this);

  @override
  String toString() => r'clipTranscriptionControllerProvider';
}

/// Transcribes one clip, on request.
///
/// **The deliberate half of the split.** Adding a clip is cheap and immediate;
/// this is the part that costs minutes of CPU, so it never starts on its own.
/// Selecting a clip reveals the action, and the user takes it.
///
/// Keyed by clip, so two clips have genuinely independent state: transcribing
/// one does not make another look busy, and a failure is attributable to the
/// clip that caused it.
///
/// Note that a clip's word timings are relative to its own media, and its
/// speaker numbering comes from its own diarization run — labels do not
/// correspond across clips (`docs/engine-architecture.md`).

abstract class _$ClipTranscriptionController
    extends $Notifier<ClipTranscriptionStatus> {
  late final _$args = ref.$arg as String;
  String get clipId => _$args;

  ClipTranscriptionStatus build(String clipId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<ClipTranscriptionStatus, ClipTranscriptionStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ClipTranscriptionStatus, ClipTranscriptionStatus>,
              ClipTranscriptionStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
