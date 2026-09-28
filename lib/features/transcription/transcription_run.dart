import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
class TranscriptionRunner {
  const TranscriptionRunner(this._ref);

  final Ref _ref;

  /// Transcribes [mediaPath] and returns the words plus whatever speaker spans
  /// survived, without touching the database.
  Future<TranscriptionOutcome> run({
    required String mediaPath,
    required StageSink onStage,
    ({int startMs, int endMs})? range,
  }) async {
    final converter = _ref.read(mediaConverterProvider);
    final whisper = _ref.read(whisperServiceProvider);

    Timer? progressTimer;
    File? slice;

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

      // A slice is a *new* file cut from the extracted WAV, never an edit of
      // it -- see the note below about what is and is not rewritten.
      if (range != null) {
        slice = File(p.join(
          (await getTemporaryDirectory()).path,
          _sliceDir,
          'range_${DateTime.now().microsecondsSinceEpoch}.wav',
        ));
        await converter.sliceWav(
          source: wav.path,
          destination: slice.path,
          startMs: range.startMs,
          endMs: range.endMs,
        );
      }
      final audio = slice ?? wav;

      // Both of these are engine parameters rather than passes over the audio,
      // so they are read here and handed to the one transcribe call.
      final language =
          await _ref.read(selectedTranscriptionLanguageProvider.future);
      final skipSilence = await _ref.read(silenceSkippingEnabledProvider.future);

      onStage(ImportStage.transcribing, percent: 0);
      startPolling();
      final result = await whisper.transcribeWav(
        audio.path,
        model: model,
        language: language,
        skipSilence: skipSilence,
      );
      stopPolling();

      final speakerSpans = await _identifySpeakers(
        wavPath: audio.path,
        result: result,
        onStage: onStage,
      );

      return (result: result, speakerSpans: speakerSpans, language: language);
    } finally {
      stopPolling();
      // Slices are scratch.
      if (slice != null) {
        try {
          await slice.delete();
        } catch (_) {}
      }
    }
  }

  /// Where range slices are written inside the cache directory.
  static const String _sliceDir = 'transcribe_slices';

  /// Removes slices a previous run left behind.
  static Future<void> sweepSlices() async {
    try {
      final dir = Directory(p.join(
        (await getTemporaryDirectory()).path,
        _sliceDir,
      ));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Diarization and its two correction passes.
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
    // anything reads them.
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
    // only thing that can reach a turn segmentation never reported.
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
