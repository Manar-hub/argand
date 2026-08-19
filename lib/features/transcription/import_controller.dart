import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/media/media_converter.dart';
import '../../core/whisper/whisper_model_controller.dart';
import '../../core/whisper/whisper_service.dart';
import 'transcript_repository.dart';

part 'import_controller.g.dart';

/// Steps the import pipeline moves through, in order. The UI maps these to
/// localized labels; the controller never holds display strings itself.
enum ImportStage { preparingModel, copyingMedia, extractingAudio, transcribing, saving }

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
    await _run(picked);
  }

  /// Resets a finished or failed run so the UI returns to its resting state.
  void reset() => state = const ImportIdle();

  Future<void> _run(PlatformFile picked) async {
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
      final media = await converter.importToAppStorage(
        projectId: projectId,
        fileName: picked.name,
        bytes: picked.readAsByteStream(),
      );

      state = const ImportRunning(ImportStage.extractingAudio);
      final wav = await converter.extractWavForTranscription(media.path);
      final duration = await converter.probeDuration(media.path);

      state = const ImportRunning(ImportStage.transcribing, percent: 0);
      _startProgressPolling(whisper);
      final result = await whisper.transcribeWav(wav.path, model: model);
      _stopProgressPolling();

      state = const ImportRunning(ImportStage.saving);
      await repository.saveImport(
        projectId: projectId,
        title: p.basenameWithoutExtension(picked.name),
        mediaPath: media.path,
        duration: duration,
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

  void _stopProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }
}
