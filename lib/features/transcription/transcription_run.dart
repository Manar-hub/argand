import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../../core/diarization/diarization_controller.dart';
import '../../core/diarization/speaker_assignment.dart';
import '../../core/diarization/speaker_diarizer.dart';
import '../../core/diarization/speaker_refiner.dart';
import '../../core/diarization/speaker_span.dart';
import '../../core/media/media_converter.dart';
import '../../core/whisper/transcription_language_controller.dart';
import '../../core/whisper/vad_controller.dart';
import '../../core/whisper/whisper_model_controller.dart';
import '../../core/whisper/whisper_service.dart';
import 'import_controller.dart' show ImportStage;
import 'transcript_repository.dart';

/// Everything one transcription run produces, ready to be written.
typedef TranscriptionOutcome = ({
  WhisperTranscribeResponse result,
  List<SpeakerSpan> speakerSpans,
  TranscriptionLanguage language,
});

/// Reports which stage the run has reached, and how far into it.
typedef StageSink = void Function(ImportStage stage, {int? percent});

/// The engine half of transcription, shared by both callers.
///
/// **Extracted because there are now two paths to the same work.** Importing a
/// file still transcribes it immediately, while a clip added to an existing
/// project is transcribed later, on request. Those differ in what they do
/// before (copy vs. nothing) and after (create a project vs. attach to a clip),
/// but the engine sequence between them — prepare the model, extract a WAV,
/// transcribe, then optionally diarize, validate and refine — must stay a
/// single copy, because it is where every measured parameter decision lives.
///
/// Holds no state and writes nothing. The caller owns the rows, the status it
/// exposes and any rollback.
class TranscriptionRunner {
  const TranscriptionRunner(this._ref);

  final Ref _ref;

  /// Transcribes [mediaPath] and returns the words plus whatever speaker spans
  /// survived, without touching the database.
  ///
  /// [onStage] is how progress reaches the UI; both callers render the same
  /// [ImportStage] labels, which is why the stage vocabulary is shared rather
  /// than duplicated per controller.
  Future<TranscriptionOutcome> run({
    required String mediaPath,
    required StageSink onStage,
  }) async {
    final converter = _ref.read(mediaConverterProvider);
    final whisper = _ref.read(whisperServiceProvider);

    Timer? progressTimer;

    // Whisper reports progress through a native atomic rather than a stream,
    // so it has to be sampled. Granularity is one whisper decode window
    // (~30s of audio), which is why this is deliberately a slow poll.
    void startPolling() {
      progressTimer?.cancel();
      progressTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
        onStage(ImportStage.transcribing, percent: whisper.progressPercent);
      });
    }

    void stopPolling() {
      progressTimer?.cancel();
      progressTimer = null;
    }

    try {
      // Copying the model out of assets happens once per model, but it is
      // slow enough on first use to deserve its own visible stage rather than
      // being hidden inside "transcribing".
      onStage(ImportStage.preparingModel);
      final model = await _ref.read(selectedWhisperModelProvider.future);
      if (model == null) {
        throw StateError('No transcription model is available in this build');
      }
      await whisper.ensureModelReady(model);

      onStage(ImportStage.extractingAudio);
      final wav = await converter.extractWavForTranscription(mediaPath);

      // Both of these are engine parameters rather than passes over the audio,
      // so they are read here and handed to the one transcribe call. Nothing
      // rewrites the extracted WAV: whisper is always fed exactly what
      // MediaConverter produced.
      final language =
          await _ref.read(selectedTranscriptionLanguageProvider.future);
      final skipSilence = await _ref.read(silenceSkippingEnabledProvider.future);

      onStage(ImportStage.transcribing, percent: 0);
      startPolling();
      final result = await whisper.transcribeWav(
        wav.path,
        model: model,
        language: language,
        skipSilence: skipSilence,
      );
      stopPolling();

      final speakerSpans = await _identifySpeakers(
        wavPath: wav.path,
        result: result,
        onStage: onStage,
      );

      return (result: result, speakerSpans: speakerSpans, language: language);
    } finally {
      stopPolling();
    }
  }

  /// Diarization and its two correction passes.
  ///
  /// **Deliberately never fatal.** A transcript without speaker labels is still
  /// the thing the user asked for, whereas failing here would throw away a
  /// transcription that already succeeded and cost the most time.
  ///
  /// Note the labels a run produces are cluster indices with meaning only
  /// inside that run, so two clips diarized separately have unrelated speaker
  /// numbering. That is a property of the engine, not of this split — see
  /// `docs/engine-architecture.md`.
  Future<List<SpeakerSpan>> _identifySpeakers({
    required String wavPath,
    required WhisperTranscribeResponse result,
    required StageSink onStage,
  }) async {
    if (!await _ref.read(speakerDiarizationEnabledProvider.future)) {
      return const <SpeakerSpan>[];
    }

    onStage(ImportStage.identifyingSpeakers, percent: 0);

    var spans = const <SpeakerSpan>[];
    try {
      spans = await _ref.read(speakerDiarizerProvider).diarize(
                wavPath,
                onProgress: (percent) => onStage(
                  ImportStage.identifyingSpeakers,
                  percent: percent,
                ),
              ) ??
          const <SpeakerSpan>[];
    } catch (error, stackTrace) {
      // Swallowed on purpose, but never silently: the words still save.
      debugPrint('Diarization failed, saving without speakers: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    // Challenges short spans segmentation appears to have invented, before
    // anything reads them. This has to come first: a spurious span edge cannot
    // be repaired downstream, because once it exists whichever side a word
    // falls on decides that word's speaker -- which is how two transcription
    // models end up disagreeing about the same audio. Uses no transcript at
    // all, so the correction is identical for every model.
    if (spans.isNotEmpty) {
      try {
        final before = spans;
        spans = await _ref
            .read(speakerRefinerProvider)
            .validateSpans(wavPath: wavPath, spans: spans);
        final changed = [
          for (var i = 0; i < spans.length; i++)
            if (spans[i].speaker != before[i].speaker) i,
        ];
        if (changed.isNotEmpty) {
          debugPrint(
              'Span validation re-labelled ${changed.length} span(s): $changed');
        }
      } catch (error, stackTrace) {
        // Swallowed like every other diarization stage: the unvalidated spans
        // are what shipped before this pass existed.
        debugPrint('Span validation failed, keeping raw spans: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    // Re-checks doubtful attributions against the audio itself, which is the
    // only thing that can reach a turn segmentation never reported. Non-fatal
    // for the same reason as diarization, one step weaker: a failure here costs
    // nothing that was not already in hand, because the unrefined spans are
    // still good.
    if (spans.isNotEmpty) {
      try {
        final words = wordTimingsOf(result);
        final refined = await _ref.read(speakerRefinerProvider).refine(
              wavPath: wavPath,
              spans: spans,
              words: words,
              assigned: assignSpeakers(words, spans),
            );
        debugPrint('Refinement: ${refined.movedCount} moved of '
            '${refined.decisions.length} candidates, '
            '${refined.embeddedRegions} embeddings, ${refined.elapsedMs}ms');
        spans = refined.spans;
      } catch (error, stackTrace) {
        debugPrint('Refinement failed, keeping unrefined spans: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    return spans;
  }
}
