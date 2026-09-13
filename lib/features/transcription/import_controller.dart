import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/diarization/diarization_controller.dart';
import '../../core/diarization/speaker_assignment.dart';
import '../../core/diarization/speaker_diarizer.dart';
import '../../core/diarization/speaker_refiner.dart';
import '../../core/diarization/speaker_span.dart';
import '../../core/media/media_converter.dart';
import '../../core/media/shared_media.dart';
import '../../core/whisper/transcription_language_controller.dart';
import '../../core/whisper/vad_controller.dart';
import '../../core/whisper/whisper_model_controller.dart';
import '../../core/whisper/whisper_service.dart';
import 'transcript_repository.dart';

part 'import_controller.g.dart';

/// Steps the import pipeline moves through, in order. The UI maps these to
/// localized labels; the controller never holds display strings itself.
///
/// Silence skipping does not appear here: it is a parameter of the transcribe
/// call rather than a pass over the audio, so it happens inside
/// [transcribing] rather than before it.
///
/// [identifyingSpeakers] is skipped when the setting is off, so this is the
/// order stages appear in, not a sequence every import runs in full.
enum ImportStage {
  preparingModel,
  copyingMedia,
  extractingAudio,
  transcribing,
  identifyingSpeakers,
  saving,
}

sealed class ImportStatus {
  const ImportStatus();
}

class ImportIdle extends ImportStatus {
  const ImportIdle();
}

/// User dismissed the picker without choosing anything. Distinct from idle so
/// the UI can acknowledge the tap instead of appearing to have ignored it.
class ImportCancelled extends ImportStatus {
  const ImportCancelled();
}

class ImportRunning extends ImportStatus {
  const ImportRunning(this.stage, {this.percent});

  final ImportStage stage;

  /// Only populated during [ImportStage.transcribing], where the engine
  /// reports real progress. Null elsewhere, meaning "indeterminate".
  final int? percent;
}

class ImportSucceeded extends ImportStatus {
  const ImportSucceeded(this.projectId);

  final String projectId;
}

class ImportFailed extends ImportStatus {
  const ImportFailed(this.error);

  final Object error;
}

/// Drives one media file from the picker all the way to persisted words.
///
/// Every step that touches the filesystem or the engine lives here rather
/// than in a widget, so the import screen can be redesigned without moving
/// any of this logic (CLAUDE.md 4).
@riverpod
class ImportController extends _$ImportController {
  Timer? _progressTimer;

  @override
  ImportStatus build() {
    ref.onDispose(() => _progressTimer?.cancel());
    return const ImportIdle();
  }

  /// Containers offered in the picker.
  ///
  /// [FileType.custom] rather than one of the presets because none of them
  /// covers this app's actual input set: `FileType.media` means video *and
  /// images* while excluding audio outright, and `FileType.audio` drops video.
  /// Android resolves these extensions to MIME types through its own
  /// `MimeTypeMap`, which does know `.mov`.
  static const _mediaExtensions = [
    'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', '3gp',
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'amr',
  ];

  /// Opens the system picker and runs the full pipeline on the chosen file.
  Future<void> importFromPicker() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _mediaExtensions,
    );
    if (picked == null) {
      state = const ImportCancelled();
      return;
    }
    await _run(
      fileName: picked.name,
      copyIn: (converter, projectId) => converter.importToAppStorage(
        projectId: projectId,
        fileName: picked.name,
        bytes: picked.readAsByteStream(),
      ),
    );
  }

  /// Runs the pipeline on a file handed over by the system share sheet.
  ///
  /// The bytes are already out of the content provider by the time this is
  /// called -- native does that, because a `content://` URI has no filesystem
  /// path and its read grant is revocable. What is left is a real file in the
  /// cache directory, which the import **adopts** rather than copies: it is
  /// about to be moved into the project, and writing a video twice to save a
  /// rename would be a poor trade on a phone.
  Future<void> importShared(SharedMedia media) async {
    state = const ImportRunning(ImportStage.copyingMedia);

    final String? cached;
    try {
      cached = await ref.read(sharedMediaChannelProvider).copy(media);
    } catch (error, stackTrace) {
      debugPrint('Could not read the shared file: $error');
      debugPrintStack(stackTrace: stackTrace);
      state = ImportFailed(error);
      return;
    }

    if (cached == null) {
      // The provider gave us nothing. Treated as a cancellation rather than a
      // failure: from the user's side nothing happened, and an error banner for
      // a share they may have dismissed would be noise.
      state = const ImportCancelled();
      return;
    }

    await _run(
      fileName: media.name,
      copyIn: (converter, projectId) => converter.adoptIntoAppStorage(
        projectId: projectId,
        fileName: media.name,
        source: File(cached!),
      ),
    );
  }

  /// Resets a finished or failed run so the UI returns to its resting state.
  void reset() => state = const ImportIdle();

  /// The pipeline, once the media is identified.
  ///
  /// [copyIn] is injected because the two entry points get the bytes into the
  /// project differently -- the picker streams them out of a URI, a share moves
  /// a file native has already written -- while everything after that point is
  /// identical and must stay that way.
  Future<void> _run({
    required String fileName,
    required Future<File> Function(MediaConverter, String projectId) copyIn,
  }) async {
    final repository = ref.read(transcriptRepositoryProvider);
    final converter = ref.read(mediaConverterProvider);
    final whisper = ref.read(whisperServiceProvider);

    final projectId = repository.newId();

    try {
      // Copying the model out of assets happens once per model, but it is
      // slow enough on first use to deserve its own visible stage rather than
      // being hidden inside "transcribing".
      state = const ImportRunning(ImportStage.preparingModel);
      final model = await ref.read(selectedWhisperModelProvider.future);
      if (model == null) {
        throw StateError('No transcription model is available in this build');
      }
      await whisper.ensureModelReady(model);

      state = const ImportRunning(ImportStage.copyingMedia);
      final media = await copyIn(converter, projectId);

      state = const ImportRunning(ImportStage.extractingAudio);
      final wav = await converter.extractWavForTranscription(media.path);
      final duration = await converter.probeDuration(media.path);

      // Both of these are engine parameters rather than passes over the audio,
      // so they are read here and handed to the one transcribe call. Nothing
      // rewrites the extracted WAV: whisper is always fed exactly what
      // MediaConverter produced.
      final language = await ref.read(selectedTranscriptionLanguageProvider.future);
      final skipSilence = await ref.read(silenceSkippingEnabledProvider.future);

      state = const ImportRunning(ImportStage.transcribing, percent: 0);
      _startProgressPolling(whisper);
      final result = await whisper.transcribeWav(
        wav.path,
        model: model,
        language: language,
        skipSilence: skipSilence,
      );
      _stopProgressPolling();

      // Runs after transcription, over the same extracted WAV. Deliberately
      // not fatal to the import: a transcript without speaker labels is still
      // the thing the user asked for, whereas failing here would throw away a
      // transcription that already succeeded and cost the most time.
      var speakerSpans = const <SpeakerSpan>[];
      if (await ref.read(speakerDiarizationEnabledProvider.future)) {
        state = const ImportRunning(ImportStage.identifyingSpeakers, percent: 0);
        try {
          speakerSpans = await ref.read(speakerDiarizerProvider).diarize(
                    wav.path,
                    onProgress: _reportDiarizationProgress,
                  ) ??
              const <SpeakerSpan>[];
        } catch (error, stackTrace) {
          // Swallowed on purpose, but never silently: the words still save.
          debugPrint('Diarization failed, saving without speakers: $error');
          debugPrintStack(stackTrace: stackTrace);
        }

        // Challenges short spans segmentation appears to have invented, before
        // anything reads them. This has to come first: a spurious span edge
        // cannot be repaired downstream, because once it exists whichever side
        // a word falls on decides that word's speaker -- which is how two
        // transcription models end up disagreeing about the same audio. Uses no
        // transcript at all, so the correction is identical for every model.
        if (speakerSpans.isNotEmpty) {
          try {
            final before = speakerSpans;
            speakerSpans = await ref
                .read(speakerRefinerProvider)
                .validateSpans(wavPath: wav.path, spans: speakerSpans);
            final changed = [
              for (var i = 0; i < speakerSpans.length; i++)
                if (speakerSpans[i].speaker != before[i].speaker) i,
            ];
            if (changed.isNotEmpty) {
              debugPrint('Span validation re-labelled ${changed.length} span(s)'
                  ': $changed');
            }
          } catch (error, stackTrace) {
            // Swallowed like every other diarization stage: the unvalidated
            // spans are what shipped before this pass existed.
            debugPrint('Span validation failed, keeping raw spans: $error');
            debugPrintStack(stackTrace: stackTrace);
          }
        }

        // Re-checks doubtful attributions against the audio itself, which is
        // the only thing that can reach a turn segmentation never reported.
        // Non-fatal for the same reason as diarization, one step weaker: a
        // failure here costs nothing that was not already in hand, because the
        // unrefined spans are still good.
        if (speakerSpans.isNotEmpty) {
          try {
            final words = wordTimingsOf(result);
            final refined = await ref.read(speakerRefinerProvider).refine(
                  wavPath: wav.path,
                  spans: speakerSpans,
                  words: words,
                  assigned: assignSpeakers(words, speakerSpans),
                );
            debugPrint('Refinement: ${refined.movedCount} moved of '
                '${refined.decisions.length} candidates, '
                '${refined.embeddedRegions} embeddings, ${refined.elapsedMs}ms');
            speakerSpans = refined.spans;
          } catch (error, stackTrace) {
            debugPrint('Refinement failed, keeping unrefined spans: $error');
            debugPrintStack(stackTrace: stackTrace);
          }
        }
      }

      state = const ImportRunning(ImportStage.saving);
      await repository.saveImport(
        projectId: projectId,
        title: p.basenameWithoutExtension(fileName),
        mediaPath: media.path,
        duration: duration,
        language: language,
        speakerSpans: speakerSpans,
        result: result,
      );

      state = ImportSucceeded(projectId);
    } catch (error) {
      _stopProgressPolling();
      // Nothing was committed to the database yet -- saveImport is the last
      // step and runs in a transaction -- so rolling back means dropping the
      // copied media, otherwise a failed import leaks a few hundred MB.
      // Guarded so a cleanup failure cannot replace the error worth reporting.
      try {
        await converter.discardProjectMedia(projectId);
      } catch (_) {
        // Ignored: the original failure below is the one the user needs.
      }
      state = ImportFailed(error);
    }
  }

  /// Whisper reports progress through a native atomic rather than a stream,
  /// so it has to be sampled. Granularity is one whisper decode window
  /// (~30s of audio), which is why this is deliberately a slow poll -- a
  /// faster one would only re-render the same number.
  void _startProgressPolling(WhisperService whisper) {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      final current = state;
      if (current is! ImportRunning || current.stage != ImportStage.transcribing) return;
      state = ImportRunning(ImportStage.transcribing, percent: whisper.progressPercent);
    });
  }

  /// Unlike whisper's progress, which has to be polled off a native atomic,
  /// diarization pushes: the native callback runs on the worker isolate and
  /// sends through a port. So this is a plain state write, not a timer.
  void _reportDiarizationProgress(int percent) {
    final current = state;
    if (current is! ImportRunning ||
        current.stage != ImportStage.identifyingSpeakers) {
      return;
    }
    state = ImportRunning(ImportStage.identifyingSpeakers, percent: percent);
  }

  void _stopProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }
}
