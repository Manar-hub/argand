// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diarization_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether imports label who is speaking.
///
/// On by default: CLAUDE.md 2 lists diarization among the core features that
/// are free and never gated, so it should happen without being asked for.
///
/// It is still a setting because it is the most expensive optional stage in the
/// pipeline — two extra models and a whole-waveform pass — and it earns nothing
/// on single-speaker media, which is most of what this app is aimed at. A user
/// who knows their video is one person talking can switch it off and get a
/// faster import, and the toggle also makes the accuracy claim measurable on
/// real media rather than only asserted.

@ProviderFor(SpeakerDiarizationEnabled)
final speakerDiarizationEnabledProvider = SpeakerDiarizationEnabledProvider._();

/// Whether imports label who is speaking.
///
/// On by default: CLAUDE.md 2 lists diarization among the core features that
/// are free and never gated, so it should happen without being asked for.
///
/// It is still a setting because it is the most expensive optional stage in the
/// pipeline — two extra models and a whole-waveform pass — and it earns nothing
/// on single-speaker media, which is most of what this app is aimed at. A user
/// who knows their video is one person talking can switch it off and get a
/// faster import, and the toggle also makes the accuracy claim measurable on
/// real media rather than only asserted.
final class SpeakerDiarizationEnabledProvider
    extends $AsyncNotifierProvider<SpeakerDiarizationEnabled, bool> {
  /// Whether imports label who is speaking.
  ///
  /// On by default: CLAUDE.md 2 lists diarization among the core features that
  /// are free and never gated, so it should happen without being asked for.
  ///
  /// It is still a setting because it is the most expensive optional stage in the
  /// pipeline — two extra models and a whole-waveform pass — and it earns nothing
  /// on single-speaker media, which is most of what this app is aimed at. A user
  /// who knows their video is one person talking can switch it off and get a
  /// faster import, and the toggle also makes the accuracy claim measurable on
  /// real media rather than only asserted.
  SpeakerDiarizationEnabledProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'speakerDiarizationEnabledProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$speakerDiarizationEnabledHash();

  @$internal
  @override
  SpeakerDiarizationEnabled create() => SpeakerDiarizationEnabled();
}

String _$speakerDiarizationEnabledHash() =>
    r'afed3854cf79c312975b959ddc253d445f3b18cd';

/// Whether imports label who is speaking.
///
/// On by default: CLAUDE.md 2 lists diarization among the core features that
/// are free and never gated, so it should happen without being asked for.
///
/// It is still a setting because it is the most expensive optional stage in the
/// pipeline — two extra models and a whole-waveform pass — and it earns nothing
/// on single-speaker media, which is most of what this app is aimed at. A user
/// who knows their video is one person talking can switch it off and get a
/// faster import, and the toggle also makes the accuracy claim measurable on
/// real media rather than only asserted.

abstract class _$SpeakerDiarizationEnabled extends $AsyncNotifier<bool> {
  FutureOr<bool> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<bool>, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool>, bool>,
              AsyncValue<bool>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
