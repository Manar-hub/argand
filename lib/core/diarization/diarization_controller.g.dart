// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diarization_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether imports label who is speaking.

@ProviderFor(SpeakerDiarizationEnabled)
final speakerDiarizationEnabledProvider = SpeakerDiarizationEnabledProvider._();

/// Whether imports label who is speaking.
final class SpeakerDiarizationEnabledProvider
    extends $AsyncNotifierProvider<SpeakerDiarizationEnabled, bool> {
  /// Whether imports label who is speaking.
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
