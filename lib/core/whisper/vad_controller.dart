import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';

part 'vad_controller.g.dart';

const String silenceSkippingSetting = 'whisper.vad';

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
@Riverpod(keepAlive: true)
class SilenceSkippingEnabled extends _$SilenceSkippingEnabled {
  static const bool defaultEnabled = true;

  @override
  Future<bool> build() async {
    final stored =
        await ref.watch(appDatabaseProvider).readSetting(silenceSkippingSetting);
    // Absent means never chosen, which is not the same as chosen-false — so
    // the default applies rather than a bare `stored == 'true'`.
    if (stored == null) return defaultEnabled;
    return stored == 'true';
  }

  Future<void> setEnabled(bool enabled) async {
    await ref
        .read(appDatabaseProvider)
        .writeSetting(silenceSkippingSetting, enabled.toString());
    state = AsyncData(enabled);
  }
}
