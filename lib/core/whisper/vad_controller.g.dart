// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vad_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether whisper.cpp is told to transcribe only the speech regions of a file.
///
/// This is voice activity detection (Silero, bundled inside the vendored
/// `whisper_ggml_plus`). It is **not** a pass over the audio: nothing rewrites
/// the extracted WAV. whisper.cpp runs VAD internally, decodes only the speech
/// it found, and maps the resulting timestamps back onto the original timeline.
///
/// **Why this and not the GTCRN denoiser** — the two answer different questions.
/// A denoiser reconstructs the waveform to suppress background noise, which on
/// already-clean speech measurably substituted correct words for wrong ones.
/// VAD only *selects* regions, so it cannot corrupt the samples it keeps, and
/// it attacks the failures actually observed on this pipeline: whisper.cpp
/// hallucinating text over silence, and the decoder repetition loops that the
/// locked `temperature = 0.0` makes more likely on non-speech audio. It is also
/// faster, since silence is never decoded. See docs/engine-architecture.md.
///
/// Exposed as a setting for the same reason the denoiser was: the claim is
/// measurable and should stay measurable on real files rather than being
/// frozen into a constant on the strength of the argument alone.

@ProviderFor(SilenceSkippingEnabled)
final silenceSkippingEnabledProvider = SilenceSkippingEnabledProvider._();

/// Whether whisper.cpp is told to transcribe only the speech regions of a file.
///
/// This is voice activity detection (Silero, bundled inside the vendored
/// `whisper_ggml_plus`). It is **not** a pass over the audio: nothing rewrites
/// the extracted WAV. whisper.cpp runs VAD internally, decodes only the speech
/// it found, and maps the resulting timestamps back onto the original timeline.
///
/// **Why this and not the GTCRN denoiser** — the two answer different questions.
/// A denoiser reconstructs the waveform to suppress background noise, which on
/// already-clean speech measurably substituted correct words for wrong ones.
/// VAD only *selects* regions, so it cannot corrupt the samples it keeps, and
/// it attacks the failures actually observed on this pipeline: whisper.cpp
/// hallucinating text over silence, and the decoder repetition loops that the
/// locked `temperature = 0.0` makes more likely on non-speech audio. It is also
/// faster, since silence is never decoded. See docs/engine-architecture.md.
///
/// Exposed as a setting for the same reason the denoiser was: the claim is
/// measurable and should stay measurable on real files rather than being
/// frozen into a constant on the strength of the argument alone.
final class SilenceSkippingEnabledProvider
    extends $AsyncNotifierProvider<SilenceSkippingEnabled, bool> {
  /// Whether whisper.cpp is told to transcribe only the speech regions of a file.
  ///
  /// This is voice activity detection (Silero, bundled inside the vendored
  /// `whisper_ggml_plus`). It is **not** a pass over the audio: nothing rewrites
  /// the extracted WAV. whisper.cpp runs VAD internally, decodes only the speech
  /// it found, and maps the resulting timestamps back onto the original timeline.
  ///
  /// **Why this and not the GTCRN denoiser** — the two answer different questions.
  /// A denoiser reconstructs the waveform to suppress background noise, which on
  /// already-clean speech measurably substituted correct words for wrong ones.
  /// VAD only *selects* regions, so it cannot corrupt the samples it keeps, and
  /// it attacks the failures actually observed on this pipeline: whisper.cpp
  /// hallucinating text over silence, and the decoder repetition loops that the
  /// locked `temperature = 0.0` makes more likely on non-speech audio. It is also
  /// faster, since silence is never decoded. See docs/engine-architecture.md.
  ///
  /// Exposed as a setting for the same reason the denoiser was: the claim is
  /// measurable and should stay measurable on real files rather than being
  /// frozen into a constant on the strength of the argument alone.
  SilenceSkippingEnabledProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'silenceSkippingEnabledProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$silenceSkippingEnabledHash();

  @$internal
  @override
  SilenceSkippingEnabled create() => SilenceSkippingEnabled();
}

String _$silenceSkippingEnabledHash() =>
    r'82b30270209ec2bce053ea804d20381355b73c8e';

/// Whether whisper.cpp is told to transcribe only the speech regions of a file.
///
/// This is voice activity detection (Silero, bundled inside the vendored
/// `whisper_ggml_plus`). It is **not** a pass over the audio: nothing rewrites
/// the extracted WAV. whisper.cpp runs VAD internally, decodes only the speech
/// it found, and maps the resulting timestamps back onto the original timeline.
///
/// **Why this and not the GTCRN denoiser** — the two answer different questions.
/// A denoiser reconstructs the waveform to suppress background noise, which on
/// already-clean speech measurably substituted correct words for wrong ones.
/// VAD only *selects* regions, so it cannot corrupt the samples it keeps, and
/// it attacks the failures actually observed on this pipeline: whisper.cpp
/// hallucinating text over silence, and the decoder repetition loops that the
/// locked `temperature = 0.0` makes more likely on non-speech audio. It is also
/// faster, since silence is never decoded. See docs/engine-architecture.md.
///
/// Exposed as a setting for the same reason the denoiser was: the claim is
/// measurable and should stay measurable on real files rather than being
/// frozen into a constant on the strength of the argument alone.

abstract class _$SilenceSkippingEnabled extends $AsyncNotifier<bool> {
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
